import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart' as intl;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Geo-Tagged Camera',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: WelcomeScreen(),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CameraScreen(),
              ),
            );
          },
          child: const Text("Start Camera"),
        ),
      ),
    );
  }
}

class CameraScreen extends StatefulWidget {
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final ImagePicker _picker = ImagePicker();
  String _currentAddress = "Fetching address...";
  String _currentDate = "";
  File? _capturedImage;
  double? _latitude;
  double? _longitude;

  @override
  void initState() {
    super.initState();
    _checkPermissionsAndFetchLocation();
  }

  Future<void> _checkPermissionsAndFetchLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _currentAddress = "Location permission denied";
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _currentAddress = "Location permissions are permanently denied";
      });
      return;
    }

    _fetchCurrentLocationAndDate();
  }

  Future<void> _fetchCurrentLocationAndDate() async {
    try {
      Position position = await Geolocator.getCurrentPosition();
      List<Placemark> placemarks =
          await placemarkFromCoordinates(position.latitude, position.longitude);
      Placemark place = placemarks[0];

      setState(() {
        _currentAddress =
            "${place.subLocality}, ${place.locality}, ${place.country}";
        _currentDate =
            intl.DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
        _latitude = position.latitude;
        _longitude = position.longitude;
      });

      print("Fetched Address: $_currentAddress");
    } catch (e) {
      setState(() {
        print("---------------------------Error: ${e.toString()}");
        _currentAddress = "Error fetching address";
        _currentDate = "Error fetching date";
        _latitude = null;
        _longitude = null;
      });

      print("Error fetching location: $e");
    }
  }

  Future<void> _captureImageWithWatermark() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.camera);
      if (image == null) return;

      setState(() {
        _capturedImage = File(image.path);
      });

      final directory = await getApplicationDocumentsDirectory();
      final watermarkedFilePath =
          '${directory.path}/${DateTime.now().millisecondsSinceEpoch}_watermarked.png';

      await _addWatermark(image.path, watermarkedFilePath);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => WatermarkedImageScreen(
            watermarkedImagePath: watermarkedFilePath,
            address: _currentAddress,
            date: _currentDate,
          ),
        ),
      );
    } catch (e) {
      print("Error during image capture: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: ${e.toString()}")),
      );
    }
  }

  Future<void> _addWatermark(
      String originalImagePath, String outputPath) async {
    final originalImage = File(originalImagePath);
    final imageBytes = await originalImage.readAsBytes();
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final paint = Paint();
    final imageSize =
        Size(frame.image.width.toDouble(), frame.image.height.toDouble());
    canvas.drawImage(frame.image, Offset.zero, paint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: "Address: $_currentAddress\nDate: $_currentDate",
        style: const TextStyle(color: Colors.white, fontSize: 24),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(20, 20));

    final picture = recorder.endRecording();
    final img = await picture.toImage(frame.image.width, frame.image.height);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

    final watermarkedBytes = byteData!.buffer.asUint8List();
    await File(outputPath).writeAsBytes(watermarkedBytes);

    print("Watermarked image saved to $outputPath");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Geo-Tagged Camera')),
      body: Column(
        children: [
          if (_capturedImage != null)
            Expanded(
              child: Image.file(
                _capturedImage!,
                fit: BoxFit.contain,
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _captureImageWithWatermark,
                icon: const Icon(Icons.camera_alt),
                label: const Text("Capture Photo"),
              ),
              const SizedBox(width: 20),
              ElevatedButton.icon(
                onPressed: () {
                  if (_capturedImage != null &&
                      _latitude != null &&
                      _longitude != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => GeoTaggedImageScreen(
                          imagePath: _capturedImage!.path,
                          latitude: _latitude!,
                          longitude: _longitude!,
                        ),
                      ),
                    );
                  } else {
                    print("Image or location data is null.");
                  }
                },
                icon: const Icon(Icons.location_on),
                label: const Text("Show Geo-Tag"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class WatermarkedImageScreen extends StatelessWidget {
  final String watermarkedImagePath;
  final String address;
  final String date;

  const WatermarkedImageScreen({
    required this.watermarkedImagePath,
    required this.address,
    required this.date,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Watermarked Image")),
      body: Column(
        children: [
          Expanded(
            child: Image.file(
              File(watermarkedImagePath),
              fit: BoxFit.contain,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              "Address: $address\nDate: $date",
              textAlign: TextAlign.center,
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text("Back to Camera"),
          ),
        ],
      ),
    );
  }
}

class GeoTaggedImageScreen extends StatelessWidget {
  final String imagePath;
  final double latitude;
  final double longitude;

  const GeoTaggedImageScreen({
    required this.imagePath,
    required this.latitude,
    required this.longitude,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Geo-Tagged Image")),
      body: Column(
        children: [
          Expanded(
            child: Image.file(
              File(imagePath),
              fit: BoxFit.contain,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              "Latitude: $latitude\nLongitude: $longitude",
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
