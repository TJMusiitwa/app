import 'dart:async';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:covidtrace/config.dart';
import 'package:covidtrace/storage/exposure.dart';
import 'package:covidtrace/storage/user.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:gact_plugin/gact_plugin.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

Future<ExposureInfo> checkExposures() async {
  print('Checking exposures...');

  var results = await Future.wait([
    UserModel.find(),
    Config.remote(),
    getApplicationSupportDirectory(),
  ]);

  var user = results[0];
  var config = results[1];
  var dir = results[2] as Directory;

  String publishedBucket = config['exposureKeysPublishedBucket'];
  String indexFileName = config['exposureKeysPublishedIndexFile'];

  var indexFile = await http
      .get('https://$publishedBucket.storage.googleapis.com/$indexFileName');
  if (indexFile.statusCode != 200) {
    return null;
  }

  // Filter objects for any that are lexically equal to or greater than
  // the CSVs we last downloaded. If we have never checked before, we
  // should fetch everything for the last three weeks
  var threeWeeksAgo = DateTime.now().subtract(Duration(days: 21));
  var lastCheck = user.lastCheck ?? threeWeeksAgo;
  var lastCsv = '${(lastCheck.millisecondsSinceEpoch / 1000).floor()}.csv';
  List<Uri> keyFiles = [];

  // Download exported zip files
  var exportFiles = indexFile.body.split('\n');
  var downloads = await Future.wait(exportFiles.where((object) {
    // TODO(wes): Store last downloaded file in DB
    return true;
  }).map((object) async {
    print('Downloading $object');
    // Download each exported zip file
    var response = await http
        .get('https://$publishedBucket.storage.googleapis.com/$object');
    if (response.statusCode != 200) {
      print(response.body);
      return null;
    }

    var keyFile = File('${dir.path}/$publishedBucket/$object');
    if (!await keyFile.exists()) {
      await keyFile.create(recursive: true);
    }
    return keyFile.writeAsBytes(response.bodyBytes);
  }));

  // Decompress and verify downloads
  keyFiles = await Future.wait(downloads.map((file) async {
    if (Platform.isAndroid) {
      return file.uri;
    }

    var archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    var first = archive.files[0];
    var second = archive.files[1];

    var bin = first.name == 'export.bin' ? first : second;
    // TODO(wes): Verify signature
    var sig = bin == first ? second : first;

    // Save bin file to disk
    var binFile = File('${file.path}.bin');
    if (!await binFile.exists()) {
      await binFile.create(recursive: true);
    }
    await binFile.writeAsBytes(bin.content as List<int>);
    return binFile.uri;
  }));

  await GactPlugin.setExposureConfiguration(
      config['exposureNotificationConfiguration']);

  await GactPlugin.setUserExplanation(
      'You were in close proximity to someone who tested positive for COVID-19.');

  // Save all found exposures
  List<ExposureInfo> exposures;
  try {
    exposures = (await GactPlugin.detectExposures(keyFiles)).toList();
    await Future.wait(exposures.map((e) {
      return ExposureModel(
        date: e.date,
        duration: e.duration,
        totalRiskScore: e.totalRiskScore,
        transmissionRiskLevel: e.transmissionRiskLevel,
      ).insert();
    }));
  } catch (err) {
    print(err);
    return null;
  }

  user.lastCheck = DateTime.now();
  await user.save();

  exposures.sort((a, b) => a.date.compareTo(b.date));
  var exposure = exposures.isNotEmpty ? exposures.last : null;

  print('Done checking exposures!');
  return exposure;
}

void showExposureNotification(ExposureInfo exposure, {Duration delay}) async {
  var date = exposure.date.toLocal();
  var dur = exposure.duration;
  var notificationPlugin = FlutterLocalNotificationsPlugin();

  var androidSpec = AndroidNotificationDetails(
      '1', 'COVID Trace', 'Exposure notifications',
      importance: Importance.Max, priority: Priority.High, ticker: 'ticker');
  var iosSpecs = IOSNotificationDetails();

  var id = 0;
  var title = 'COVID-19 Exposure Alert';
  var body =
      'On ${DateFormat.EEEE().add_MMMd().format(date)} you were in close proximity to someone for ${dur.inMinutes} minutes who tested positive for COVID-19.';
  var details = NotificationDetails(androidSpec, iosSpecs);
  var payload = 'Default_Sound';

  if (delay != null) {
    await notificationPlugin.schedule(
        id, title, body, DateTime.now().add(delay), details,
        payload: payload);
  } else {
    await notificationPlugin.show(id, title, body, details, payload: payload);
  }
}
