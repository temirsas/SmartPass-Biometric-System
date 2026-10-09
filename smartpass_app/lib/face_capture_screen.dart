import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceCaptureScreen extends StatefulWidget {
  final int userId;

  const FaceCaptureScreen({super.key, required this.userId});

  @override
  State<FaceCaptureScreen> createState() => _FaceCaptureScreenState();
}

class _FaceCaptureScreenState extends State<FaceCaptureScreen> {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  bool _isUploading = false;
  bool _isProcessingImage = false;

  String _scanText = 'Поместите лицо в рамку';
  Color _frameColor = Colors.white;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: false,
      enableLandmarks: false,
      enableTracking: false,
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );

      await _controller!.initialize();
      if (mounted) {
        setState(() => _isCameraInitialized = true);
        _startNeuralNetworkStream();
      }
    } catch (e) {
      debugPrint("Ошибка камеры: $e");
    }
  }

  void _startNeuralNetworkStream() {
    _controller!.startImageStream((CameraImage image) {
      if (_isProcessingImage || _isUploading) return;
      _processCameraImage(image);
    });
  }

  Future<void> _processCameraImage(CameraImage image) async {
    _isProcessingImage = true;

    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());

      // Динамическое определение правильного поворота камеры
      InputImageRotation imageRotation;
      switch (_controller!.description.sensorOrientation) {
        case 90:
          imageRotation = InputImageRotation.rotation90deg;
          break;
        case 180:
          imageRotation = InputImageRotation.rotation180deg;
          break;
        case 270:
          imageRotation = InputImageRotation.rotation270deg;
          break;
        default:
          imageRotation = InputImageRotation.rotation0deg;
      }

      final InputImageFormat inputImageFormat = Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888;

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: imageRotation,
          format: inputImageFormat,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );

      final List<Face> faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        if (mounted) {
          setState(() {
            _scanText = 'Лицо распознано!';
            _frameColor = Colors.greenAccent;
          });
        }
        await _controller!.stopImageStream();
        await _captureAndUpload();
      } else {
        if (mounted && _scanText != 'Поместите лицо в рамку') {
          setState(() {
            _scanText = 'Поместите лицо в рамку';
            _frameColor = Colors.white;
          });
        }
      }
    } catch (e) {
      debugPrint("ML Error: $e");
    } finally {
      _isProcessingImage = false;
    }
  }

  Future<void> _captureAndUpload() async {
    setState(() => _isUploading = true);

    try {
      final XFile file = await _controller!.takePicture();

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('http://10.0.2.2:8000/biometrics/upload/'),
      );
      request.fields['user_id'] = widget.userId.toString();

      final bytes = await file.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: 'face.jpg'));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        if (!mounted) return;
        Navigator.pop(context, true);
      } else {
        final error = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(error['detail']);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Ошибка: $e'), backgroundColor: Colors.red),
      );
      Navigator.pop(context, false);
    }
  }

  @override
  void dispose() {
    _faceDetector.close();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),

          ColorFiltered(
            colorFilter: ColorFilter.mode(Colors.black.withAlpha(217), BlendMode.srcOut),
            child: Container(
              decoration: const BoxDecoration(color: Colors.transparent),
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  width: 280,
                  height: 380,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(200),
                  ),
                ),
              ),
            ),
          ),

          Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 280,
              height: 380,
              decoration: BoxDecoration(
                  border: Border.all(color: _frameColor, width: 4),
                  borderRadius: BorderRadius.circular(200),
                  boxShadow: [
                    if (_frameColor == Colors.greenAccent)
                      BoxShadow(color: Colors.greenAccent.withAlpha(128), blurRadius: 20, spreadRadius: 5)
                  ]
              ),
            ),
          ),

          Positioned(
            top: 100,
            left: 0,
            right: 0,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                _scanText,
                key: ValueKey<String>(_scanText),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          if (_isUploading)
            const Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: Center(child: CircularProgressIndicator(color: Colors.greenAccent)),
            ),

          Positioned(
            top: 50,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 32),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}