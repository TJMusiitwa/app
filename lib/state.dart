import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:covidtrace/storage/db.dart';
import 'package:gact_plugin/gact_plugin.dart';
import 'package:http/http.dart' as http;
import 'package:package_info/package_info.dart';
import 'package:sqflite/sqflite.dart';

import 'config.dart';
import 'helper/check_exposures.dart' as bg;
import 'package:flutter/foundation.dart';
import 'storage/exposure.dart';
import 'storage/report.dart';
import 'storage/user.dart';

class NotificationState with ChangeNotifier {
  static final instance = NotificationState();

  void onNotice(String notice) {
    notifyListeners();
  }
}

class AppState with ChangeNotifier {
  static UserModel _user;
  static ReportModel _report;
  static bool _ready = false;
  static ExposureModel _exposure;
  static AuthorizationStatus _status;

  AppState() {
    initState();
    NotificationState.instance.addListener(() async {
      setExposure(await getExposure());
    });
  }

  initState() async {
    _user = await UserModel.find();
    _report = await ReportModel.findLatest();
    _exposure = await getExposure();
    _status = await checkStatus();
    _ready = true;
    notifyListeners();
  }

  bool get ready => _ready;

  ExposureModel get exposure => _exposure;

  UserModel get user => _user;

  AuthorizationStatus get status => _status;

  Future<ExposureModel> getExposure() async {
    var rows = await ExposureModel.findAll(limit: 1, orderBy: 'date DESC');

    return rows.isNotEmpty ? rows.first : null;
  }

  void setExposure(ExposureModel exposure) {
    _exposure = exposure;
    notifyListeners();
  }

  Future<AuthorizationStatus> checkStatus() async {
    _status = await GactPlugin.authorizationStatus;
    notifyListeners();
    return _status;
  }

  Future<ExposureModel> checkExposures() async {
    await bg.checkExposures();
    _user = await UserModel.find();
    _exposure = await getExposure();
    notifyListeners();
    return _exposure;
  }

  Future<void> saveUser(user) async {
    _user = user;
    await _user.save();
    notifyListeners();
  }

  ReportModel get report => _report;

  Future<void> saveReport(ReportModel report) async {
    _report = report;
    await _report.create();
    notifyListeners();
  }

  Future<List<ExposureKey>> sendExposureKeys(
      Map<String, dynamic> config, String verificationCode) async {
    Iterable<ExposureKey> keys;

    try {
      // Note that using `testMode: true` will include today's exposure key
      // which will be rejected by the exposure server if included.
      keys = await GactPlugin.getExposureKeys(testMode: false);
    } catch (err) {
      print(err);
      if (errorFromException(err) == ErrorCode.notAuthorized) {
        return null;
      }
    }

    if (keys == null || keys.isEmpty) {
      return keys?.toList();
    }

    var cert = await verifyCode(verificationCode, keys);
    if (cert == null) {
      return null;
    }

    var postData = {
      "regions": ['US'],
      "appPackageName": (await PackageInfo.fromPlatform()).packageName,
      "temporaryExposureKeys": keys
          .map((k) => {
                "key": k.keyData,
                "rollingPeriod": k.rollingPeriod,
                "rollingStartNumber": k.rollingStartNumber,
                "transmissionRisk": k.transmissionRiskLevel
              })
          .toList(),
      "verificationPayload": cert,
      "hmackey": base64.encode(utf8.encode(_user.uuid)),
    };

    var postResp = await http.post(
      Uri.parse(config['exposurePublishUrl']),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(postData),
    );

    if (postResp.statusCode == 200) {
      return keys.toList();
    } else {
      throw (postResp.body);
    }
  }

  Future<bool> sendReport(String verificationCode) async {
    var success = false;
    var config = await Config.remote();

    List<ExposureKey> keys =
        await sendExposureKeys(config, verificationCode) ?? [];

    if (keys.isNotEmpty) {
      _report = ReportModel(
          lastExposureKey: keys.last.keyData, timestamp: DateTime.now());
      await report.create();
      success = true;
    }

    notifyListeners();
    return success;
  }

  Future<String> verifyCode(
      String verificationCode, Iterable<ExposureKey> keys) async {
    var config = await Config.remote();

    var uri = Uri.parse('${config['verifyUrl']}/api/verify');
    var postResp = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': config['verifyApiKey']
      },
      body: jsonEncode({"code": verificationCode}),
    );
    print(postResp.body);

    var statusCode = postResp.statusCode;
    if (statusCode == 429) {
      throw ('Too many attempts. Please wait and try again later');
    } else if (statusCode == 500) {
      throw ('Unable to verify your code');
    } else if (statusCode != 200) {
      throw (postResp.body);
    }

    var body = jsonDecode(postResp.body);
    var token = body['token'];
    var testType = body['testtype'];

    if (testType != 'confirmed') {
      throw ('Only a confirmed positive diagnosis is supported');
    }

    // Calculate and submit HMAC
    // See: https://developers.google.com/android/exposure-notifications/verification-system#hmac-calc
    var hmacSha256 = new Hmac(sha256, utf8.encode(_user.uuid));
    var sortedKeys = keys.toList();
    sortedKeys.sort((a, b) => a.keyData.compareTo(b.keyData));
    var bytes = sortedKeys
        .map((k) =>
            '${k.keyData}.${k.rollingStartNumber}.${k.rollingPeriod}.${k.transmissionRiskLevel}')
        .join(',');
    var digest = hmacSha256.convert(utf8.encode(bytes));

    uri = Uri.parse('${config['verifyUrl']}/api/certificate');
    postResp = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': config['verifyApiKey']
      },
      body:
          jsonEncode({"token": token, 'ekeyhmac': base64.encode(digest.bytes)}),
    );

    print(postResp.body);
    if (postResp.statusCode != 200) {
      throw (postResp.body);
    }

    body = jsonDecode(postResp.body);
    var certificate = body['certificate'];

    return certificate;
  }

  Future<void> clearReport() async {
    await ReportModel.destroyAll();
    _report = null;
    notifyListeners();
  }

  Future<void> resetInfections() async {
    final Database db = await Storage.db;
    await Future.wait([
      db.update('user', {'last_check': null, 'last_key_file': null}),
      ExposureModel.destroyAll(),
    ]);
    _exposure = null;
    notifyListeners();
  }
}
