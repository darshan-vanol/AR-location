import 'dart:async';

import 'package:ar_demo/main.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';

class ChooseLocationScreen extends StatefulWidget {
  const ChooseLocationScreen({super.key});

  @override
  State<ChooseLocationScreen> createState() => _ChooseLocationScreenState();
}

class _ChooseLocationScreenState extends State<ChooseLocationScreen> {
  List<Property> properties = [];

  final Completer<GoogleMapController> mapController = Completer<GoogleMapController>();
  Location location = Location();

  @override
  void initState() {
    requestPermission();
    super.initState();
  }

  requestPermission() async {
    var serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        return;
      }
    }

    var permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Location'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (context) => PropertyARView(properties: properties)));
        },
        child: const Icon(Icons.check),
      ),
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
          Expanded(
            child: GoogleMap(
                initialCameraPosition: const CameraPosition(target: LatLng(0, 0), zoom: 18),
                onMapCreated: onMapCreated,
                onTap: onLocationSelected,
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                markers: properties
                    .map((property) => Marker(markerId: MarkerId(property.name.toString()), position: LatLng(property.latitude, property.longitude)))
                    .toSet()),
          ),
          SingleChildScrollView(
            child: Column(
              children: properties
                  .map((property) => ListTile(
                        title: Text(property.name),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () {
                            setState(() {
                              properties.remove(property);
                            });
                          },
                        ),
                      ))
                  .toList(),
            ),
          )
        ]),
      ),
    );
  }

  onLocationSelected(LatLng location) async {
    final result = await showDialog(
        context: context,
        builder: (context) {
          TextEditingController controller = TextEditingController();
          return AlertDialog(
            title: const Text('Location Selected'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Latitude: ${location.latitude}, Longitude: ${location.longitude}'),
                TextField(
                  decoration: const InputDecoration(labelText: 'Name'),
                  controller: controller,
                )
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(false);
                },
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  final name = controller.text;
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a name')));
                    return;
                  }
                  if (properties.any((element) => element.name == name)) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name already exists')));
                    return;
                  }
                  properties.add(Property(name: name, latitude: location.latitude, longitude: location.longitude, key: GlobalKey()));
                  Navigator.of(context).pop(true);
                },
                child: const Text('OK'),
              )
            ],
          );
        });

    if (result == true) {
      setState(() {});
    }
  }

  onMapCreated(GoogleMapController controller) {
    mapController.complete(controller);

    location.getLocation().then((locationData) {
      controller.moveCamera(CameraUpdate.newLatLng(LatLng(locationData.latitude!, locationData.longitude!)));
    });
  }
}
