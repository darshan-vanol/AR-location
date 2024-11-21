// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'dart:math';

import 'package:ar_demo/direction_indicator.dart';

import 'package:ar_demo/location_choose_screen.dart';
import 'package:ar_location_view/ar_annotation.dart';
import 'package:ar_location_view/ar_location_widget.dart';
import 'package:arkit_plugin/arkit_plugin.dart';
import 'package:flutter/material.dart';
import 'package:arcore_flutter_plugin/arcore_flutter_plugin.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
  List<Annotation> annotations = [];

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

    currentPosition = await Geolocator.getCurrentPosition();

    if (currentPosition != null) {
      //create fake position near to current positio

      List<(String, Position)> propertyPositions = widget.properties.map((e) {
        final geoPoint = CoordinateAdjuster.adjustPropertyCoordinates(
            GeoPoint(currentPosition!.latitude, currentPosition!.longitude), GeoPoint(e.latitude, e.longitude));

        return (
          e.name,
          Position(
            latitude: geoPoint.latitude,
            longitude: geoPoint.longitude,
            altitude: currentPosition!.altitude,
            timestamp: currentPosition!.timestamp,
            accuracy: currentPosition!.accuracy,
            altitudeAccuracy: currentPosition!.altitudeAccuracy,
            heading: currentPosition!.heading,
            headingAccuracy: currentPosition!.headingAccuracy,
            speed: currentPosition!.speed,
            speedAccuracy: currentPosition!.speedAccuracy,
          )
        );
      }).toList();

      annotations = propertyPositions.map((e) {
        return Annotation(
          uid: e.$1,
          position: e.$2,
        );
      }).toList();

      setState(() {});
    }
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
                // Platform.isAndroid
                // ? ArCoreView(
                //     onArCoreViewCreated: _onArCoreViewCreated,
                //     // enableUpdateListener: true,
                //     enableTapRecognizer: true,
                //     // enablePlaneRenderer: true,
                //     // debug: true,
                //     type: ArCoreViewType.STANDARDVIEW,
                //   )

                // ?
                ArLocationWidget(
                  annotations: annotations,
                  annotationHeight: 120,
                  annotationViewBuilder: (context, annotation) {
                    return InkWell(
                      onTap: () => onNodeTap(annotation.uid),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.location_on, color: Colors.red),
                                SizedBox(width: 4),
                                Text(annotation.uid, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(annotation.distanceFromUser.toStringAsFixed(2) + ' meters'),
                            const SizedBox(height: 5),
                            Text('Price: \$100,000'),
                            const SizedBox(height: 5),
                          ],
                        ),
                      ),
                    );
                  },
                  scaleWithDistance: true,
                  maxVisibleDistance: 100,
                  onLocationChange: (position) {
                    print("Location changed: ${position.latitude}, ${position.longitude}");
                  },
                )

                // ? ARview
                // : ARKitSceneView(
                //     onARKitViewCreated: onARKitViewCreated,
                //     // debug: true,
                //     enableTapRecognizer: true,
                //     showStatistics: true,
                //     // worldAlignment: ARWorldAlignment.camera,
                //   ),
                ,
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
    // await Future.delayed(const Duration(milliseconds: 500));
    locationdata = await location.getLocation();
    for (final property in properties) {
      if (currentBearing == null) continue;

      // await IOSARHelper.placeObjectInAR(
      //   arKitController: arKitController,
      //   targetLat: property.latitude,
      //   targetLon: property.longitude,
      //   targetAlt: property.altitude,
      //   currentLat: locationdata!.latitude!,
      //   currentLon: locationdata!.longitude!,
      //   currentAlt: locationdata!.altitude!,
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
        diffuse: ARKitMaterialProperty.image('/assets/pin.png'),
      );
      final plane = ARKitPlane(
        materials: [material],
      );

      final rotation = quaternionFromMatrix(lookAtMatrix);

      print("Rotation: $rotation");

      final node = ARKitNode(
        name: property.name,
        geometry: plane,
        position: position,
        rotation: rotation,
        scale: vector.Vector3(
          2,
          2,
          2,
        ),
      );

      // final node = ARKitGltfNode(
      //   name: property.name,
      //   assetType: AssetType.flutterAsset,
      //   url: '/assets/map_pin_location_pin.glb',
      //   position: position,
      //   scale: vector.Vector3(2, 2, 2),
      // );

      await arKitController.add(node);
      print("Added node: ${property.name}");
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

    controller.onNodeTap = onNodeTap;
    locationdata = await location.getLocation();

    for (final property in properties) {
      await _addPropertyCard(arCoreController!, property);
    }

    // controller.resume();
  }

  void onNodeTap(String name) {
    print("Tapped on $name");

    final property = properties.firstWhere((element) => element.name == name);

    // final distance = locationService.calculateDistance(
    //   locationdata!.latitude!,
    //   locationdata!.longitude!,
    //   property.latitude,
    //   property.longitude,
    // );

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            // Text('Distance: ${distance.toStringAsFixed(2)} meters'),
            const SizedBox(height: 10),
            Text('Price: ${property.price}'),
            const SizedBox(height: 10),
            Text('Latitude: ${property.latitude}, Longitude: ${property.longitude}'),
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

    // final propertyCardImage = await _captureWidgetToImage(property.key);
    final bytes = (await rootBundle.load('assets/pin.png')).buffer.asUint8List();

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
        bytes: bytes,
        height: 300,
        width: 300,
      ),
      position: position,
      scale: vector.Vector3(4.0, 4.0, 4.0),
      // rotation: quaternionFromMatrix(lookAtMatrix),
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

/*   void fetchAndCalculateDeclination() async {
    // Step 1: Get the current location
    locationdata = await location.getLocation();
    if (locationdata == null) {
      print("Unable to retrieve location.");
      return;
    }

    double latitude = locationdata!.latitude!;
    double longitude = locationdata!.longitude!;
    double altitude = locationdata!.altitude ?? 0.0; // Use 0 if altitude is not available

    // Step 2: Fetch the magnetic declination
    double? declination = await getMagneticDeclination(latitude, longitude, altitude);

    if (declination != null) {
      print("Magnetic Declination: $declination°");
    } else {
      print("Could not retrieve magnetic declination.");
    }
  }

  Future<double?> getMagneticDeclination(double latitude, double longitude, double altitude) async {
    final DateTime now = DateTime.now();
    final String url = 'https://www.ngdc.noaa.gov/geomag-web/calculators/calculateDeclination';

    try {
      final response =
          await http.get(Uri.parse('$url?lat1=$latitude&lon1=$longitude&resultFormat=json&model=WMM&altitude=$altitude&year=${now.year}&key=zNEw7'));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['result'][0]['declination']; // This gives magnetic declination in degrees
      } else {
        print('Failed to fetch declination data: ${response.statusCode}');
      }
    } catch (e) {
      print('Error occurred while fetching declination: $e');
    }
    return null;
  }
 */
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
    yield* compass.map((event) => event.heading != null
        ? Platform.isIOS
            ? (event.heading! + 30) % 360
            : event.heading!
        : 0.0);
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
    double distance = calculateDistance(
      _lastPosition.latitude!,
      _lastPosition.longitude!,
      currentLocation.latitude!,
      currentLocation.longitude!,
    );
    return distance >= threshold;
  }

  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
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

class Annotation extends ArAnnotation {
  Annotation({
    required super.uid,
    required super.position,
  });
}

class GeoPoint {
  final double latitude;
  final double longitude;

  GeoPoint(this.latitude, this.longitude);
}

class CoordinateAdjuster {
  static const double _earthRadiusKm = 6371.0;

  /// Adjusts property coordinates by rotating them 30 degrees left from user's perspective
  /// [userLocation] - Current user's location (latitude, longitude)
  /// [propertyLocation] - Original property location (latitude, longitude)
  /// Returns adjusted property coordinates
  static GeoPoint adjustPropertyCoordinates(
    GeoPoint userLocation,
    GeoPoint propertyLocation,
  ) {
    // Convert degrees to radians
    final userLat = _toRadians(userLocation.latitude);
    final userLon = _toRadians(userLocation.longitude);
    final propertyLat = _toRadians(propertyLocation.latitude);
    final propertyLon = _toRadians(propertyLocation.longitude);

    // Calculate initial bearing
    final dLon = propertyLon - userLon;
    final y = sin(dLon) * cos(propertyLat);
    final x = cos(userLat) * sin(propertyLat) - sin(userLat) * cos(propertyLat) * cos(dLon);
    var bearing = atan2(y, x);

    // Adjust bearing by 30 degrees to the left
    bearing = bearing - _toRadians(29);

    // Calculate distance between points
    final distance = _calculateDistance(userLocation, propertyLocation);

    // Calculate new coordinates
    final newLat = asin(
      sin(userLat) * cos(distance / _earthRadiusKm) + cos(userLat) * sin(distance / _earthRadiusKm) * cos(bearing),
    );

    final newLon = userLon +
        atan2(
          sin(bearing) * sin(distance / _earthRadiusKm) * cos(userLat),
          cos(distance / _earthRadiusKm) - sin(userLat) * sin(newLat),
        );

    return GeoPoint(
      _toDegrees(newLat),
      _toDegrees(newLon),
    );
  }

  /// Calculates the distance between two points in kilometers
  static double _calculateDistance(GeoPoint point1, GeoPoint point2) {
    final lat1 = _toRadians(point1.latitude);
    final lon1 = _toRadians(point1.longitude);
    final lat2 = _toRadians(point2.latitude);
    final lon2 = _toRadians(point2.longitude);

    final dLat = lat2 - lat1;
    final dLon = lon2 - lon1;

    final a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return _earthRadiusKm * c;
  }

  static double _toRadians(double degrees) => degrees * pi / 180;
  static double _toDegrees(double radians) => radians * 180 / pi;
}
