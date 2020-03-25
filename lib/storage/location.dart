import 'dart:async';
import 'db.dart';
import 'package:s2geometry/s2geometry.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/datetime.dart';

class LocationModel {
  final int id;
  final double longitude;
  final double latitude;
  final double speed;
  final int sample;
  final String activity;
  final DateTime timestamp;

  bool exposure;
  S2CellId cellID;

  LocationModel(
      {this.id,
      this.longitude,
      this.latitude,
      this.speed,
      this.activity,
      this.sample,
      this.timestamp,
      this.exposure}) {
    cellID = new S2CellId.fromLatLng(
        new S2LatLng.fromDegrees(this.latitude, this.longitude));
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'longitude': longitude,
      'latitude': latitude,
      'cell_id': cellID
          .parent(
              22) // TODO(Josh) configure 22 somehow? this represents area of 4.8 m^2
          .toToken(),
      'activity': activity,
      'sample': sample,
      'speed': speed,
      'timestamp': timestamp.toIso8601String(),
      'exposure': exposure == true ? 1 : 0,
    };
  }

  List<dynamic> toCSV() {
    return [roundedDateTime(timestamp), cellID.toToken(), 'self'];
  }

  Future<void> save() async {
    final Database db = await Storage.db;
    return db.update('location', toMap(), where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> insert(LocationModel location) async {
    final Database db = await Storage.db;
    await db.insert('location', location.toMap());
    print('inserted location $location');
  }

  static Future<Map<String, int>> count() async {
    var db = await Storage.db;

    var count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM location;'));

    var exposures = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM location WHERE exposure = 1;'));

    return {'count': count, 'exposures': exposures};
  }

  static Future<List<LocationModel>> findAll(
      {int limit,
      String where,
      List<dynamic> whereArgs,
      String orderBy,
      String groupBy}) async {
    var rows = await findAllRaw(
        limit: limit,
        orderBy: orderBy,
        where: where,
        whereArgs: whereArgs,
        groupBy: groupBy);

    return List.generate(rows.length, (i) {
      return LocationModel(
        id: rows[i]['id'],
        longitude: rows[i]['longitude'],
        latitude: rows[i]['latitude'],
        activity: rows[i]['activity'],
        sample: rows[i]['sample'],
        speed: rows[i]['speed'],
        timestamp: DateTime.parse(rows[i]['timestamp']),
        exposure: rows[i]['exposure'] == 1,
      );
    });
  }

  static Future<List<Map<String, dynamic>>> findAllRaw(
      {List<String> columns,
      int limit,
      String where,
      List<dynamic> whereArgs,
      String orderBy,
      String groupBy}) async {
    final Database db = await Storage.db;

    return await db.query('location',
        columns: columns,
        limit: limit,
        orderBy: orderBy,
        where: where,
        whereArgs: whereArgs,
        groupBy: groupBy);
  }

  static Future<void> destroyAll() async {
    final Database db = await Storage.db;
    await db.delete('location');
  }
}