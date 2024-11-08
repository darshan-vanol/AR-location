// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'dart:math';

import 'package:ar_demo/direction_indicator.dart';
import 'package:ar_demo/ios_ar_helper.dart';
import 'package:ar_demo/location_choose_screen.dart';
import 'package:arkit_plugin/arkit_plugin.dart';
import 'package:flutter/material.dart';
import 'package:arcore_flutter_plugin/arcore_flutter_plugin.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:vector_math/vector_math_64.dart' as vector;

void main() {
  print("Hello");
  runApp(const MyApp());
}

class Property {
  final String name;
  final String? price;
  final String? bedCount;
  final String? bathCount;
  final double latitude;
  final double longitude;
  final double? altitude;
  final GlobalKey key;

  Property({
    required this.name,
    this.bedCount,
    this.price,
    this.bathCount,
    required this.latitude,
    required this.longitude,
    this.altitude,
    required this.key,
  });
}

// final List<Property> properties = [
//   // Property(
//   //   name: 'McDonalds',
//   //   price: 'McDonalds',
//   //   bedCount: '3',
//   //   bathCount: '2',
//   //   latitude: 23.192479005088746,
//   //   longitude: 72.6164854830734,
//   //   altitude: 47.0,
//   //   key: GlobalKey(),
//   // ),
//   Property(
//     name: 'Point A', // padhar deri
//     price: 'Point A',
//     bedCount: '3',
//     bathCount: '2',
//     latitude: 23.292862804904445,
//     longitude: 71.8129295837378,
//     altitude: -13.0,
//     key: GlobalKey(),
//   ),
//   // Property(
//   //   name: 'Nayara Petrol pump',
//   //   price: 'Nayara Petrol pump',
//   //   bedCount: '4',
//   //   bathCount: '3',
//   //   latitude: 23.192041849966913,
//   //   longitude: 72.61233988105963,
//   //   altitude: 47.0,
//   //   key: GlobalKey(),
//   // ),
//   Property(
//     name: 'Point B', // Delo 2
//     price: 'Point B',
//     bedCount: '4',
//     bathCount: '3',
//     latitude: 23.29326034342297,
//     longitude: 71.81278513099004,
//     altitude: -13.0,
//     key: GlobalKey(),
//   ),
//   // Property(
//   //   name: 'Khetlapa',
//   //   price: 'Khetlapa',
//   //   bedCount: '5',
//   //   bathCount: '4',
//   //   latitude: 23.193304928478646,
//   //   longitude: 72.61495523568317,
//   //   altitude: 46.0,
//   //   key: GlobalKey(),
//   // ),
//   Property(
//     name: 'Point C', // Bhagaba dukan
//     price: 'Point C',
//     bedCount: '5',
//     bathCount: '4',
//     latitude: 23.29293024005034,
//     longitude: 71.81272466851638,
//     altitude: -13.0,
//     key: GlobalKey(),
//   ),
//   Property(
//     name: 'Ratnaraj  I-502',
//     price: 'Ratnaraj  I-502',
//     bedCount: '5',
//     bathCount: '4',
//     latitude: 23.19285755324716,
//     longitude: 72.61311728884499,
//     altitude: -13.0,
//     key: GlobalKey(),
//   ),
// ];

// Earth radius constant (in meters)
const double earthRadius = 6378137.0;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AR Real Estate',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const ChooseLocationScreen(),
    );
  }
}

class PropertyARView extends StatefulWidget {
  final List<Property> properties;
  const PropertyARView({super.key, required this.properties});

  @override
  _PropertyARViewState createState() => _PropertyARViewState();
}

class _PropertyARViewState extends State<PropertyARView> {
  ArCoreController? arCoreController;
  Position? currentPosition;
  double? currentBearing;
  StreamSubscription<CompassEvent>? compassSubscription;
  StreamSubscription<Position>? positionSubscription;
  LocationService locationService = LocationService(threshold: 10);
  bool isPermissionGranted = false;
  Location location = Location();
  LocationData? locationdata;
  GoogleMapController? googleMapController;
  List<Property> properties = [];
  StreamSubscription<double>? compassStream;

  @override
  void initState() {
    properties = widget.properties;
    super.initState();
    requestPermission();
    initializeCompass();
  }

  requestPermission() async {
    isPermissionGranted = await locationService.requestPermission();
    setState(() {});
  }

  void initializeLocation() {
    location.getLocation().then((value) {
      locationdata = value;
    });
  }

  void initializeCompass() {
    compassStream = getCurrentBearing().listen((bearing) {
      currentBearing = bearing;
      updateMapCameraDirection(bearing);

      if (arCoreController != null) {
        arCoreController!.resume();
      }
    });
  }

  vector.Vector3 gpsToLocalSpace(
    double targetLat,
    double targetLon,
    double? targetAlt,
    double deviceBearing,
    // Position currentPosition,
  ) {
    final userLon = locationdata!.longitude!;
    final userLat = locationdata!.latitude!;
    final userAlt = locationdata!.altitude!;

    final userLatRad = userLat * (pi / 180.0);
    final userLonRad = userLon * (pi / 180.0);
    final targetLatRad = targetLat * (pi / 180.0);
    final targetLonRad = targetLon * (pi / 180.0);

    final dLon = targetLonRad - userLonRad;

    final y = sin(dLon) * cos(targetLatRad);
    final x = cos(userLatRad) * sin(targetLatRad) - sin(userLatRad) * cos(targetLatRad) * cos(dLon);

    var bearing = atan2(y, x);
    bearing = (bearing * 180.0 / pi + 360.0) % 360.0;

    var relativeAngle = (bearing - deviceBearing + 360.0) % 360.0;
    relativeAngle = (relativeAngle - 30) % 360.0;
    relativeAngle = relativeAngle * (pi / 180.0);

    const fixedDistance = 5.0;

    final localX = fixedDistance * sin(relativeAngle);
    final localZ = -fixedDistance * cos(relativeAngle);
    // final localX = sin(relativeAngle);
    // final localZ = -cos(relativeAngle);

    double localY = 0.0;
    if (targetAlt != null) {
      localY = (targetAlt - userAlt) * 0.1;
    }

    print("Target: $targetLat, $targetLon");
    print("User: $userLat, $userLon, $userAlt");
    print("Bearing: $bearing°");
    print("Device Bearing: $deviceBearing°");
    print("Relative Angle: ${relativeAngle * (180.0 / pi)}°");
    print("Position: X:$localX, Y:$localY, Z:$localZ");

    return vector.Vector3(localX, localY, localZ);
  }

  /* vector.Vector3 gpsToLocalSpace(
    double targetLat,
    double targetLon,
    double? targetAlt,
    double deviceBearing,
  ) {
    final userLon = locationdata!.longitude!;
    final userLat = locationdata!.latitude!;
    final userAlt = locationdata!.altitude!;

    // Calculate distance and initial bearing to target
    final dLat = (targetLat - userLat) * (pi / 180.0);
    final dLon = (targetLon - userLon) * (pi / 180.0);

    // Haversine formula for more accurate distance calculation
    final a = sin(dLat / 2) * sin(dLat / 2) + cos(userLat * pi / 180.0) * cos(targetLat * pi / 180.0) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    final distance = earthRadius * c;

    // Calculate bearing to target
    final y = sin(dLon) * cos(targetLat * pi / 180.0);
    final x = cos(userLat * pi / 180.0) * sin(targetLat * pi / 180.0) - sin(userLat * pi / 180.0) * cos(targetLat * pi / 180.0) * cos(dLon);
    var bearing = atan2(y, x);
    bearing = (bearing * 180 / pi + 360) % 360; // Convert to degrees

    // Calculate relative angle considering device orientation
    final relativeAngle = (bearing - deviceBearing) * (pi / 180.0);

    // Convert to local space coordinates
    final localX = distance * sin(relativeAngle);
    final localZ = distance * cos(relativeAngle);

    double localY = 0.0;

    if (targetAlt != null) {
      localY = targetAlt - userAlt;
    }

    // Scale down the distances to be more manageable in AR space
    const scaleFactor = 0.1; // Adjust this value to change the apparent distance
    return vector.Vector3(
      localX * scaleFactor,
      localY * scaleFactor,
      localZ * scaleFactor,
    );
  } */

  Future<void> _updatePropertyPositions(Position currentPosition, double currentBearing) async {
    for (final property in properties) {
      await arCoreController?.removeNode(nodeName: property.name);

      final propertyCardImage = await _captureWidgetToImage(property.key);

      final position = gpsToLocalSpace(
        property.latitude,
        property.longitude,
        property.altitude,
        currentBearing,
        // currentPosition,
      );

      final lookAtMatrix = lookAt(
        position,
        vector.Vector3(0, 0, 0),
        vector.Vector3(0, 1, 0),
      );

      final propertyNode = ArCoreNode(
        name: property.name,
        image: ArCoreImage(
          bytes: propertyCardImage,
          height: 300,
          width: 500,
        ),
        position: position,
        rotation: quaternionFromMatrix(lookAtMatrix),
      );

      await arCoreController?.addArCoreNodeWithAnchor(propertyNode);
    }
    arCoreController?.resume();
  }

  updateMapCameraDirection(double bearing) {
    if (googleMapController == null || locationdata == null) return;
    googleMapController?.moveCamera(CameraUpdate.newCameraPosition(
      CameraPosition(
        target: LatLng(locationdata!.latitude!, locationdata!.longitude!),
        zoom: 18,
        bearing: bearing,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(
      //   title: const Text('AR Real Estate'),
      // ),
      body: isPermissionGranted
          ? Stack(
              children: [
                ...properties.map((property) => _buildPropertyCard(property)),
                Platform.isAndroid
                    ? ArCoreView(
                        onArCoreViewCreated: _onArCoreViewCreated,
                        // enableUpdateListener: true,
                        enableTapRecognizer: true,
                        // enablePlaneRenderer: true,
                        // debug: true,
                        type: ArCoreViewType.STANDARDVIEW,
                      )
                    : ARKitSceneView(
                        onARKitViewCreated: onARKitViewCreated,
                        debug: true,
                        enableTapRecognizer: true,
                        showStatistics: true,
                        worldAlignment: ARWorldAlignment.camera,
                      ),
                Align(
                  alignment: Alignment.bottomRight,
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width * 0.4,
                    height: MediaQuery.of(context).size.height * 0.3,
                    child: Stack(
                      children: [
                        GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: LatLng(properties.first.latitude, properties.first.longitude),
                            bearing: 0,
                            zoom: 15,
                          ),
                          onMapCreated: onMapCreated,
                          compassEnabled: false,
                          scrollGesturesEnabled: false,
                          zoomGesturesEnabled: false,
                          zoomControlsEnabled: false,
                          myLocationEnabled: true,
                          markers: properties.map((property) {
                            return Marker(
                              markerId: MarkerId(property.name),
                              position: LatLng(property.latitude, property.longitude),
                              infoWindow: InfoWindow(
                                title: property.name,
                                snippet: 'Beds: ${property.bedCount}, Baths: ${property.bathCount}',
                              ),
                            );
                          }).toSet(),
                        ),
                        Align(
                          alignment: Alignment.topCenter,
                          child: LayoutBuilder(
                            builder: (context, constraints) => Align(
                              alignment: Alignment.topCenter,
                              child: DirectionIndicator(
                                color: Colors.red,
                                height: constraints.maxHeight * 0.5,
                                width: constraints.maxWidth * 0.6,
                                opacity: 0.8,
                              ),
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ],
            )
          : Center(
              child: Column(
              children: [
                const Text(
                  "Please grant location permission",
                  style: TextStyle(fontSize: 20),
                ),
                ElevatedButton(
                  onPressed: () {
                    requestPermission();
                  },
                  child: const Text('Grant Permission'),
                ),
              ],
            )),
    );
  }

  void onMapCreated(GoogleMapController controller) async {
    googleMapController = controller;

    while (locationdata == null) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    controller.moveCamera(CameraUpdate.newLatLng(LatLng(locationdata!.latitude!, locationdata!.longitude!)));
  }

  void onARKitViewCreated(ARKitController arKitController) async {
//sleep for 500ms to wait for ARCore to initialize
    await Future.delayed(const Duration(milliseconds: 500));

    for (final property in properties) {
      if (currentPosition == null || currentBearing == null) continue;

      final image = await _captureWidgetToImageBase64(property.key);

      // await IOSARHelper.placeObjectInAR(
      //   arKitController: arKitController,
      //   targetLat: property.latitude,
      //   targetLon: property.longitude,
      //   targetAlt: property.altitude,
      //   currentLat: currentPosition!.latitude,
      //   currentLon: currentPosition!.longitude,
      //   currentAlt: currentPosition!.altitude,
      //   bearing: currentBearing!,
      //   base64Image: image,
      //   nodeName: property.name,
      // );

      final position = ARGPSConverter.gpsToLocalSpace(
        userAlt: locationdata!.altitude!,
        deviceBearing: currentBearing!,
        userLat: locationdata!.latitude!,
        userLon: locationdata!.longitude!,
        targetAlt: property.altitude,
        targetLat: property.latitude,
        targetLon: property.longitude,
      );
      final lookAtMatrix = lookAt(
        position,
        vector.Vector3(0, 0, 0),
        vector.Vector3(0, 1, 0),
      );

      final material = ARKitMaterial(
        doubleSided: true,
        lightingModelName: ARKitLightingModel.constant,
        diffuse: ARKitMaterialProperty.image(image),
      );
      final plane = ARKitPlane(
        width: 2, // Adjust size as needed
        height: 1,
        materials: [material],
      );
      final node = ARKitNode(
          name: property.name,
          geometry: plane,
          position: position,
          rotation: quaternionFromMatrix(lookAtMatrix),
          scale: vector.Vector3(
            3.5,
            3.5,
            3.5,
          ));

      arKitController.add(node);
    }

    arKitController.onNodeTap = (names) => onNodeTap(names.first);

    /*  // Update positions when compass or location changes
    Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (currentPosition != null && currentBearing != null) {
        for (final property in properties) {
          final image = await _captureWidgetToImageBase64(property.key);

          // Remove existing node
          await arKitController.remove(property.name);

          // Add updated node
          await IOSARHelper.placeObjectInAR(
            arKitController: arKitController,
            targetLat: property.latitude,
            targetLon: property.longitude,
            targetAlt: property.altitude,
            currentLat: currentPosition!.latitude,
            currentLon: currentPosition!.longitude,
            currentAlt: currentPosition!.altitude,
            bearing: currentBearing!,
            base64Image: image,
            nodeName: property.name,
          );
        }
      }
    }); */
  }

  void _onArCoreViewCreated(ArCoreController controller) async {
    arCoreController = controller;

    arCoreController?.onError = (error) => print('Error: $error');

    /*    locationService.getPositionStream().listen((position) {
      print("Position: ${position.latitude}, ${position.longitude}, ${position.altitude}");
    }); */

    // CombineLatestStream.combine2(
    //   getCurrentPosition().asyncMap((position) async {
    //     await Future.delayed(const Duration(seconds: 2));
    //     return position;
    //   }),
    //   getCurrentBearing().asyncMap((bearing) async {
    //     await Future.delayed(const Duration(seconds: 2));
    //     return bearing;
    //   }),
    //   (Position position, double bearing) => [position, bearing],
    // ).listen(
    //   (event) async {
    //     currentPosition = event[0] as Position;
    //     currentBearing = event[1] as double;
    //     await _updatePropertyPositions(currentPosition!, currentBearing!);
    //   },
    // );

    locationdata = await location.getLocation();

    for (final property in properties) {
      _addPropertyCard(controller, property);
    }

    controller.onNodeTap = onNodeTap;
    controller.resume();
  }

  void onNodeTap(String name) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildPropertyDetail('bed', '3'),
                _buildPropertyDetail('bath', '2'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addPropertyCard(
    ArCoreController controller,
    Property property,
    // Position currentPosition,
    // double currentBearing,
  ) async {
    if (currentBearing == null) return;

    final propertyCardImage = await _captureWidgetToImage(property.key);

    final position = ARGPSConverter.gpsToLocalSpace(
      userAlt: locationdata!.altitude!,
      deviceBearing: currentBearing!,
      userLat: locationdata!.latitude!,
      userLon: locationdata!.longitude!,
      targetAlt: property.altitude,
      targetLat: property.latitude,
      targetLon: property.longitude,
    );

    // final position = gpsToLocalSpace(
    //   property.latitude,
    //   property.longitude,
    //   property.altitude,
    //   currentBearing!,
    // );

    print("Position: $position");

    final lookAtMatrix = lookAt(
      position,
      vector.Vector3(0, 0, 0),
      vector.Vector3(0, 1, 0),
    );

    final propertyNode = ArCoreNode(
      name: property.name,
      image: ArCoreImage(
        bytes: propertyCardImage,
        height: 300,
        width: 500,
      ),
      position: position,
      scale: vector.Vector3(2.0, 2.0, 2.0),
      rotation: quaternionFromMatrix(lookAtMatrix),
    );

    controller.addArCoreNode(propertyNode);
  }

  Widget _buildPropertyCard(Property property) {
    return RepaintBoundary(
      key: property.key,
      child: Card(
        // margin: const EdgeInsets.all(8),
        color: Colors.white,
        elevation: 2,
        shadowColor: Colors.grey,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.location_on_sharp,
              color: Colors.red,
            ),
            const SizedBox(
              width: 10,
            ),
            Text(
              property.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPropertyDetail(String type, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(type == 'bed' ? Icons.king_bed : Icons.bathtub),
        Text(value),
      ],
    );
  }

  Future<Uint8List> _captureWidgetToImage(GlobalKey widgetKey) async {
    RenderRepaintBoundary boundary = widgetKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    var image = await boundary.toImage(pixelRatio: 3.0);
    ByteData? byteData = await image.toByteData(format: ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<String> _captureWidgetToImageBase64(GlobalKey widgetKey) async {
    RenderRepaintBoundary boundary = widgetKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    var image = await boundary.toImage(pixelRatio: 3.0); // Added pixelRatio for better quality
    ByteData? byteData = await image.toByteData(format: ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    final base64String = base64Encode(bytes);
    return 'data:image/png;base64,$base64String'; // Added data URI prefix
  }

  @override
  void dispose() {
    arCoreController?.dispose();
    compassSubscription?.cancel();
    compassStream?.cancel();
    positionSubscription?.cancel();
    googleMapController?.dispose();
    super.dispose();
  }

  vector.Matrix4 lookAt(vector.Vector3 position, vector.Vector3 target, vector.Vector3 up) {
    final z = (position - target).normalized();
    final x = up.cross(z).normalized();
    final y = z.cross(x);

    final matrix = vector.Matrix4.zero();
    matrix.setColumn(0, vector.Vector4(x.x, x.y, x.z, 0));
    matrix.setColumn(1, vector.Vector4(y.x, y.y, y.z, 0));
    matrix.setColumn(2, vector.Vector4(z.x, z.y, z.z, 0));
    matrix.setColumn(3, vector.Vector4(position.x, position.y, position.z, 1));

    return matrix;
  }
}

vector.Vector4 quaternionFromMatrix(vector.Matrix4 matrix) {
  final q = vector.Quaternion.fromRotation(matrix.getRotation());
  return vector.Vector4(q.x, q.y, q.z, q.w);
}

/* Stream<Position> getCurrentPosition() async* {
  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      yield* Stream.error('Location permissions are denied');
      return;
    }
  }

  if (permission == LocationPermission.deniedForever) {
    yield* Stream.error('Location permissions are permanently denied, we cannot request permissions.');
    return;
  }

  Stream<Position> position = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
    accuracy: LocationAccuracy.high,
  ));

  yield* position;
}
 */
Stream<double> getCurrentBearing() async* {
  Stream<CompassEvent>? compass = FlutterCompass.events;
  if (compass != null) {
    yield* compass.map((event) => event.heading ?? 0.0);
  }
}

Widget getSimplePropertyCard(Property property) {
  return RepaintBoundary(
    key: property.key,
    child: Container(
      color: Colors.deepPurple,
      padding: const EdgeInsets.all(20),
      child: Text(
        property.name,
        style: const TextStyle(color: Colors.white, fontSize: 60, fontWeight: FontWeight.bold),
      ),
    ),
  );
}

/* Future<Position> getCurrentPositionFuture() async {
  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      throw Exception('Location permissions are denied');
    }
  }

  if (permission == LocationPermission.deniedForever) {
    throw Exception('Location permissions are permanently denied, we cannot request permissions.');
  }

  Position position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
    accuracy: LocationAccuracy.high,
  ));

  return position;
}
 */
class LocationService {
  final Location _location = Location();
  late LocationData _lastPosition;
  PermissionStatus? _permission;
  final double threshold; // Distance threshold in meters

  LocationService({required this.threshold});

  Future<bool> requestPermission() async {
    _permission = await _location.requestPermission();
    return _permission == PermissionStatus.granted;
  }

  Future<void> _initializeLastPosition() async {
    _lastPosition = await _location.getLocation();
  }

  // Function that returns a filtered stream of positions
  Stream<LocationData> getPositionStream() async* {
    await _initializeLastPosition();

    yield* _location.onLocationChanged.asyncExpand((currentLocation) async* {
      if (_shouldUpdatePosition(currentLocation)) {
        _lastPosition = currentLocation;
        yield currentLocation;
      }
    });
  }

  bool _shouldUpdatePosition(LocationData currentLocation) {
    double distance = _calculateDistance(
      _lastPosition.latitude!,
      _lastPosition.longitude!,
      currentLocation.latitude!,
      currentLocation.longitude!,
    );
    return distance >= threshold;
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // in meters
    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLon = _degreesToRadians(lon2 - lon1);

    final double a = sin(dLat / 2) * sin(dLat / 2) + cos(_degreesToRadians(lat1)) * cos(_degreesToRadians(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) => degrees * pi / 180;
}

class ARGPSConverter {
  static const double earthRadius = 6371000; // Earth's radius in meters

  static vector.Vector3 gpsToLocalSpace({
    required double targetLat,
    required double targetLon,
    double? targetAlt,
    required double deviceBearing,
    required double userLat,
    required double userLon,
    required double userAlt,
  }) {
    // Convert to radians
    final userLatRad = radians(userLat);
    final userLonRad = radians(userLon);
    final targetLatRad = radians(targetLat);
    final targetLonRad = radians(targetLon);

    // Calculate actual distance using Haversine formula
    final dLat = targetLatRad - userLatRad;
    final dLon = targetLonRad - userLonRad;

    final a = sin(dLat / 2) * sin(dLat / 2) + cos(userLatRad) * cos(targetLatRad) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    final actualDistance = earthRadius * c;

    // Calculate true bearing
    final y = sin(dLon) * cos(targetLatRad);
    final x = cos(userLatRad) * sin(targetLatRad) - sin(userLatRad) * cos(targetLatRad) * cos(dLon);
    var bearing = degrees(atan2(y, x));
    bearing = (bearing + 360.0) % 360.0;

    // Calculate relative angle (removed the 30-degree offset)
    var relativeAngle = (bearing - deviceBearing + 360.0) % 360.0;
    relativeAngle = radians(relativeAngle); // Convert to radians for sin/cos

    // Calculate AR space coordinates using actual distance
    final localX = actualDistance * sin(relativeAngle);
    final localZ = -actualDistance * cos(relativeAngle);

    // Calculate height if target altitude is provided
    double localY = 0.0;
    if (targetAlt != null) {
      localY = targetAlt - userAlt;
    }

    // Debug information
    print("""
GPS Conversion Debug Info:
Target: Lat: $targetLat, Lon: $targetLon, Alt: $targetAlt
User: Lat: $userLat, Lon: $userLon, Alt: $userAlt
Actual Distance: ${actualDistance.toStringAsFixed(2)} meters
True Bearing: ${bearing.toStringAsFixed(2)}°
Device Bearing: ${deviceBearing.toStringAsFixed(2)}°
Relative Angle: ${degrees(relativeAngle).toStringAsFixed(2)}°
AR Position: X: ${localX.toStringAsFixed(2)}, Y: ${localY.toStringAsFixed(2)}, Z: ${localZ.toStringAsFixed(2)}
    """);

    return vector.Vector3(localX, localY, localZ);
  }

  /// Helper method to convert degrees to radians
  static double radians(double degrees) => degrees * pi / 180.0;

  /// Helper method to convert radians to degrees
  static double degrees(double radians) => radians * 180.0 / pi;
}
