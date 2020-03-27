import 'dart:async';
import 'package:covidtrace/helper/location.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'storage/location.dart';
import 'storage/user.dart';
import 'package:latlong/latlong.dart' as lt;

final Map<String, Icon> activities = {
  'unknown': Icon(Icons.not_listed_location),
  'still': Icon(Icons.location_on),
  'on_foot': Icon(Icons.directions_walk),
  'walking': Icon(Icons.directions_walk),
  'running': Icon(Icons.directions_run),
  'on_bicycle': Icon(Icons.directions_bike),
  'in_vehicle': Icon(Icons.directions_car),
};

class LocationHistory extends StatefulWidget {
  @override
  LocationHistoryState createState() => LocationHistoryState();
}

class LocationHistoryState extends State {
  String _filter = 'all';
  List<LocationModel> _locations = [];
  List<LocationModel> _display = [];
  LocationModel _selected;
  Future<LatLng> _currentLocation;
  Future<void> _initLoad;
  Completer<GoogleMapController> _controller = Completer();
  ScrollController _scroller = ScrollController();
  List<Marker> _markers = [];
  UserModel _user;

  @override
  void initState() {
    super.initState();
    _initLoad = loadLocations();
    loadUser();
    currentLocation();
  }

  loadUser() async {
    var user = await UserModel.find();
    setState(() => _user = user);
  }

  Future<LatLng> currentLocation() async {
    var loc = locateCurrentPosition();
    setState(() => _currentLocation = loc);

    return await loc;
  }

  Future<void> loadLocations() async {
    var locations = await LocationModel.findAll(
        where: 'sample = 0', orderBy: 'timestamp DESC');
    setState(() => _locations = locations);
    setFilter(_filter);
  }

  setFilter(String value) {
    var locations = value == 'exposed'
        ? _locations.where((l) => l.exposure).toList()
        : _locations;

    setState(() {
      _filter = value;
      _display = locations;
    });

    setLocation(_display.length > 0 ? _display.first : null);
    _scroller.animateTo(0.0,
        duration: Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  setLocation(LocationModel item, {bool open = false}) async {
    if (item == null) {
      setState(() {
        _selected = null;
        _markers = [];
      });

      return;
    }

    var loc = LatLng(item.latitude, item.longitude);
    setState(() {
      _selected = item;
      _markers = [
        Marker(markerId: MarkerId(item.id.toString()), position: loc)
      ];
    });

    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(CameraUpdate.newLatLng(loc));

    if (open && Theme.of(context).platform == TargetPlatform.iOS) {
      launch('https://maps.apple.com?q=${loc.latitude},${loc.longitude}',
          forceSafariVC: false);
    }
  }

  lt.LatLng toLtLatLng(LatLng loc) {
    return lt.LatLng(loc.latitude, loc.longitude);
  }

  @override
  Widget build(BuildContext context) {
    var enableLocation = _user?.latitude != null;

    return Scaffold(
        appBar: AppBar(title: Text('Location History')),
        body: Column(children: [
          FutureBuilder(
              future: _currentLocation,
              builder: (context, AsyncSnapshot<LatLng> snapshot) {
                if (snapshot.connectionState != ConnectionState.done ||
                    !snapshot.hasData ||
                    _user?.home == null) {
                  return Container();
                }

                var currentPosition = snapshot.data;
                var home = lt.Circle(toLtLatLng(_user.home), _user.homeRadius);
                var nearHome = home.isPointInside(toLtLatLng(currentPosition));

                return Container(
                    color: Colors.blueGrey,
                    child: ListTileTheme(
                      textColor: Colors.white,
                      iconColor: Colors.white,
                      child: ListTile(
                        trailing: Icon(
                          nearHome ? Icons.location_off : Icons.location_on,
                          size: 35,
                        ),
                        title: Text(nearHome
                            ? 'Near your home'
                            : 'Location tracking on'),
                        subtitle: Text(nearHome
                            ? 'Location tracking is off.'
                            : 'The location history is only on your phone.'),
                      ),
                    ));
              }),
          Flexible(
              flex: 2,
              child: Stack(children: [
                FutureBuilder(
                    future: _initLoad,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return Container();
                      }

                      return GoogleMap(
                        mapType: MapType.normal,
                        myLocationEnabled: enableLocation,
                        myLocationButtonEnabled: false,
                        initialCameraPosition: CameraPosition(
                            target: _selected != null
                                ? LatLng(
                                    _selected.latitude, _selected.longitude)
                                : LatLng(0, 0),
                            zoom: 16),
                        markers: _markers.toSet(),
                        circles: _user?.home != null
                            ? [
                                new Circle(
                                    circleId: CircleId('home'),
                                    center: _user.home,
                                    radius: _user.homeRadius,
                                    fillColor: Colors.red.withOpacity(.2),
                                    strokeColor: Colors.red,
                                    strokeWidth: 2)
                              ].toSet()
                            : Set(),
                        onMapCreated: (GoogleMapController controller) {
                          _controller.complete(controller);
                        },
                      );
                    }),
                Positioned(
                    left: 0,
                    right: 0,
                    bottom: 15.0,
                    child: Center(
                        child: CupertinoSlidingSegmentedControl(
                            backgroundColor: Color(0xCCCCCCCC),
                            padding: EdgeInsets.all(5),
                            groupValue: _filter,
                            children: {
                              'all': Text('All Locations'),
                              'exposed': Text('Potential Exposures'),
                            },
                            onValueChanged: setFilter))),
              ])),
          Divider(
            height: 0,
            color: Colors.grey,
          ),
          Flexible(
              flex: 3,
              child: RefreshIndicator(
                  onRefresh: loadLocations,
                  child: ListView.builder(
                    controller: _scroller,
                    itemCount: _display.length,
                    itemBuilder: (context, i) {
                      var item = _display[i];
                      var timestamp = item.timestamp.toLocal();
                      var selected = _selected.id == item.id;

                      return Column(children: [
                        ListTileTheme(
                            selectedColor: Colors.black,
                            child: Container(
                                color: selected
                                    ? Colors.grey[200]
                                    : Colors.transparent,
                                child: ListTile(
                                  selected: selected,
                                  onLongPress: () =>
                                      setLocation(item, open: true),
                                  onTap: () => setLocation(item),
                                  title: Text(
                                      '${DateFormat.Md().format(timestamp)}'),
                                  subtitle: Text(
                                      '${DateFormat.jms().format(timestamp)}'),
                                  trailing: Icon(
                                      item.exposure
                                          ? Icons.warning
                                          : Icons.place,
                                      color: selected
                                          ? Colors.red
                                          : item.exposure
                                              ? Colors.orange
                                              : Colors.grey),
                                ))),
                        Divider(height: 0),
                      ]);
                    },
                  )))
        ]));
  }
}
