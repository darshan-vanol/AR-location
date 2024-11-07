import 'dart:math';

import 'package:arkit_plugin/arkit_plugin.dart';
import 'package:vector_math/vector_math_64.dart';

class IOSARHelper {
  static Future<void> placeObjectInAR({
    required ARKitController arKitController,
    required double targetLat,
    required double targetLon,
    required double? targetAlt,
    required double currentLat,
    required double currentLon,
    required double currentAlt,
    required double bearing,
    required String base64Image,
    String? nodeName,
  }) async {
    arKitController.add(ARKitNode(
      name: 'sphere',
      geometry: ARKitSphere(radius: 0.1),
      position: Vector3(0, 0, -1),
    ));

    // Calculate distance and bearing between points
    final distance = calculateDistance(
      currentLat,
      currentLon,
      targetLat,
      targetLon,
    );

    final bearingToTarget = calculateBearing(
      currentLat,
      currentLon,
      targetLat,
      targetLon,
    );

    // Convert to radians
    final bearingRad = (bearing) * (pi / 180.0);
    double relativeBearing = (bearingToTarget - bearing + 360) % 360;
    relativeBearing = (relativeBearing - 30) % 360;
    final relativeAngleRad = relativeBearing * (pi / 180.0);

    // Scale distance for AR space (you might need to adjust this scale factor)
    final scaledDistance = distance; // Scale down the distance

    // Calculate position in AR space
    final x = scaledDistance * sin(relativeAngleRad);
    final z = -scaledDistance * cos(relativeAngleRad);

    double y = 0.0;

    if (targetAlt != null) {
      y = (targetAlt - currentAlt) * 0.1; // Scale height difference
    }

    final position = Vector3(x, y, z);

    // Create the plane with image
    final material = ARKitMaterial(
      doubleSided: true,
      lightingModelName: ARKitLightingModel.constant,
      diffuse: ARKitMaterialProperty.image(base64Image),
    );

    final plane = ARKitPlane(
      width: 2, // Adjust size as needed
      height: 1,
      materials: [material],
    );

    // Calculate rotation to face the user
    final rotationY = relativeAngleRad;
    final rotation = Vector4(0, 1, 0, rotationY);

    final node = ARKitNode(
        name: nodeName ?? "ar_node",
        geometry: plane,
        position: position,
        rotation: rotation,
        scale: Vector3(
          3.5,
          3.5,
          3.5,
        ));

    await arKitController.add(node);
  }

  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371e3; // Earth's radius in meters
    final phi1 = lat1 * pi / 180;
    final phi2 = lat2 * pi / 180;
    final deltaPhi = (lat2 - lat1) * pi / 180;
    final deltaLambda = (lon2 - lon1) * pi / 180;

    final a = sin(deltaPhi / 2) * sin(deltaPhi / 2) + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  static double calculateBearing(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final phi1 = lat1 * pi / 180;
    final phi2 = lat2 * pi / 180;
    final lambda1 = lon1 * pi / 180;
    final lambda2 = lon2 * pi / 180;

    final y = sin(lambda2 - lambda1) * cos(phi2);
    final x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(lambda2 - lambda1);
    final bearing = atan2(y, x) * 180 / pi;
    return (bearing + 360) % 360;
  }
}
