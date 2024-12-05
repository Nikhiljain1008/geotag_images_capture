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
import 'package:gallery_saver/gallery_saver.dart';

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
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      List<Placemark> placemarks =
          await placemarkFromCoordinates(position.latitude, position.longitude);
      Placemark place = placemarks[0];

      setState(() {
        _currentAddress =
            "${place.name}, ${place.street}, ${place.subLocality}, "
            "${place.locality}, ${place.administrativeArea}, ${place.postalCode}, "
            "${place.country}";
        _currentDate =
            intl.DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
        _latitude = position.latitude;
        _longitude = position.longitude;
      });

      print("Fetched Address: $_currentAddress");
      print("Latitude: $_latitude, Longitude: $_longitude");
    } catch (e) {
      setState(() {
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

      // Save the watermarked image to the gallery
      await GallerySaver.saveImage(watermarkedFilePath).then((success) {
        if (success != null && success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Image saved to gallery")),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Failed to save image to gallery")),
          );
        }
      });

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

    // Text to add to the watermark
    final watermarkText = "Address: $_currentAddress\n"
        "Date: $_currentDate\n"
        "Latitude: ${_latitude?.toStringAsFixed(6)}\n"
        "Longitude: ${_longitude?.toStringAsFixed(6)}";

    // Define text style and maximum width for wrapping
    final textStyle = TextStyle(color: Colors.white, fontSize: 80);
    final maxWidth = imageSize.width - 20; // Padding of 20 on each side

    // Calculate the wrapped text
    final wrappedTextLines = _wrapText(watermarkText, textStyle, maxWidth);

    // Draw each line of text on the canvas
    double yOffset = imageSize.height - 20; // Start near the bottom
    for (String line in wrappedTextLines.reversed) {
      final textPainter = TextPainter(
        text: TextSpan(text: line, style: textStyle),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout(maxWidth: maxWidth);

      yOffset -= textPainter.height + 5; // Adjust position for each line
      textPainter.paint(canvas, Offset(20, yOffset));
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(frame.image.width, frame.image.height);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

    final watermarkedBytes = byteData!.buffer.asUint8List();
    await File(outputPath).writeAsBytes(watermarkedBytes);

    print("Watermarked image saved to $outputPath");
  }

// Helper function to wrap text into multiple lines
  List<String> _wrapText(String text, TextStyle style, double maxWidth) {
    final words = text.split(' ');
    List<String> lines = [];
    String currentLine = "";

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
    );

    for (String word in words) {
      final testLine = (currentLine.isEmpty ? "" : "$currentLine ") + word;
      textPainter.text = TextSpan(text: testLine, style: style);
      textPainter.layout();

      if (textPainter.width <= maxWidth) {
        currentLine = testLine;
      } else {
        lines.add(currentLine);
        currentLine = word;
      }
    }

    if (currentLine.isNotEmpty) {
      lines.add(currentLine);
    }

    return lines;
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
