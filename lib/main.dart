import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/rendering.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const MyApp({required this.cameras, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Geo-Tagged Camera',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: WelcomeScreen(cameras: cameras),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  final List<CameraDescription> cameras;

  const WelcomeScreen({required this.cameras, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CameraScreen(cameras: cameras),
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
  final List<CameraDescription> cameras;

  const CameraScreen({required this.cameras, Key? key}) : super(key: key);

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  String _currentAddress = "Fetching address...";
  String _currentDate = "";
  File? _capturedImage;

  final GlobalKey _globalKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _fetchCurrentLocationAndDate();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    _controller = CameraController(
      widget.cameras[0],
      ResolutionPreset.high,
      enableAudio: false,
    );
    _initializeControllerFuture = _controller.initialize();
    setState(() {});
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
        _currentDate = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
      });
    } catch (e) {
      setState(() {
        _currentAddress = "Error fetching address";
        _currentDate = "Error fetching date";
      });
    }
  }

  Future<void> _captureImageWithWatermark() async {
    try {
      await _initializeControllerFuture;

      final image = await _controller.takePicture();
      setState(() {
        _capturedImage = File(image.path);
      });

      final directory = await getApplicationDocumentsDirectory();
      final watermarkedFilePath =
          '${directory.path}/${DateTime.now().millisecondsSinceEpoch}_watermarked.png';

      // Save image with watermark
      await _addWatermark(image.path, watermarkedFilePath);

      // Navigate to the new page with the watermarked image
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: ${e.toString()}")),
      );
    }
  }

  Future<void> _addWatermark(
      String originalImagePath, String outputPath) async {
    RenderRepaintBoundary boundary =
        _globalKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    ui.Image image = await boundary.toImage();
    ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    Uint8List pngBytes = byteData!.buffer.asUint8List();

    File(outputPath).writeAsBytesSync(pngBytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Geo-Tagged Camera')),
      body: RepaintBoundary(
        key: _globalKey,
        child: Column(
          children: [
            Expanded(
              child: FutureBuilder<void>(
                future: _initializeControllerFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done) {
                    return CameraPreview(_controller);
                  } else {
                    return const Center(child: CircularProgressIndicator());
                  }
                },
              ),
            ),
            ElevatedButton.icon(
              onPressed: _captureImageWithWatermark,
              icon: const Icon(Icons.camera_alt),
              label: const Text("Capture Photo"),
            ),
          ],
        ),
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
          Text(
            "Address: $address",
            textAlign: TextAlign.center,
          ),
          Text(
            "Date: $date",
            textAlign: TextAlign.center,
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
