import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:latlong/latlong.dart' as LL;

Res parse(String data) {
  return Res.from(json.decode(data));
}

class Res {
  int time;
  List<Vector> vectors;

  Res([this.time, this.vectors]);

  factory Res.from(Map<String, dynamic> json) {
    var vectors = List<Vector>();
    if (json["states"] != null) {
      for (var s in json["states"]) {
        Vector v = Vector.from(s);
        if (vectors.length < 99 && v.name != null && v.lat != null &&
            v.lng != null && v.speed != null && v.bearing != null && v.alt != null) {
          vectors.add(v);
        }
      }
    }
    return Res(json["time"] as int, vectors);
  }
}

class Vector {
  String id, name;
  double lng, lat, speed, bearing, alt;

  Vector({this.id, this.name, this.lng, this.lat, this.speed, this.bearing, this.alt});

  factory Vector.from(dynamic json) {
    return Vector(
      id: json[0].toString(),
      name: json[1]?.toString(),
      lng: json[5]?.toDouble(),
      lat: json[6]?.toDouble(),
      speed: json[9]?.toDouble(),
      bearing: json[10]?.toDouble(),
      alt: json[13]?.toDouble(),
    );
  }
}

void main() => runApp(App());

class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'Flight Tracker', home: Home());
  }
}

class Home extends StatefulWidget {
  @override
  State<Home> createState() => HomeState();
}

class HomeState extends State<Home> {
  CameraPosition _lastPos;
  var _pos = CameraPosition(target: LatLng(37.4, -122));
  var _ctrl = StreamController<Res>();
  Timer _timer;
  String _url;
  DateTime _lastReq;
  Size _size;
  bool _enabled;

  double _lat(double h, double s) {
    return 90*(-1+(4*atan(pow(e,(pi-(2*pi*(((s/2)-(s*log(tan((pi/4)+((_pos.target.latitude*pi/180)/2)))/(2*pi)))+h))/s))))/pi);
  }

  Future<void> _get(Size size) async {
    _lastReq = DateTime.now();
    _size = size;
    var s = pow(2, _pos.zoom) * 256;
    var x = size.width / (s / 180);
    var h = size.height / 2;
    var l = _pos.target.longitude;
    _url = "https://opensky-network.org/api/states/all?lamin=${_lat(h,s)}&lomin=${l-x}&lamax=${_lat(-h,s)}&lomax=${l+x}";
    _ctrl.add(await compute(parse, (await get(_url)).body));
  }

  Set<Marker> _buildMarkers(Res res) {
    var markers = Set<Marker>();
    if (res?.vectors != null) {
      for (var v in res.vectors) {
        markers.add(Marker(
          markerId: MarkerId(v.id),
          icon: BitmapDescriptor.fromAsset("m.png"),
          infoWindow: InfoWindow(
            title: v.name,
            snippet: "${(v.alt * 3.28084).round()}ft ${(v.speed * 1.94384).round()}kn",
          ),
          position: LatLng(v.lat, v.lng),
          rotation: v.bearing,
        ));
      }
    }
    return markers;
  }

  void _update(Res res) {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(milliseconds: 16), (t) async {
      if (_lastReq != null && DateTime.now().difference(_lastReq).inSeconds >= 10) {
        _get(_size);
      }
      if (res?.vectors != null && _pos.zoom > 9) {
        var vectors = List<Vector>();
        for (var v in res.vectors) {
          var l = LL.Distance().offset(LL.LatLng(v.lat, v.lng), 0.02 * v.speed, v.bearing);
          vectors.add(Vector(
            alt: v.alt,
            name: v.name,
            id: v.id,
            lat: l.latitude,
            lng: l.longitude,
            bearing: v.bearing,
            speed: v.speed,
          ));
        }
        _ctrl.add(Res(0, vectors));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: StreamBuilder(
        stream: _ctrl.stream,
        builder: (context, snapshot) {
          _update(snapshot.data);
          return GoogleMap(
            myLocationEnabled: _enabled,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            initialCameraPosition: _pos,
            minMaxZoomPreference: MinMaxZoomPreference(3, 17),
            markers: _buildMarkers(snapshot.data),
            onMapCreated: (c) async {
              await PermissionHandler().requestPermissions([PermissionGroup.location]);
              setState(() => _enabled = true);
            },
            onCameraMove: (p) => _pos = p,
            onCameraIdle: () async {
              if (_pos != _lastPos) {
                _lastPos = _pos;
                await _get(context.size);
              }
            },
          );
        },
      ),
    );
  }
}
