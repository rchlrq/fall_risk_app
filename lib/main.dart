import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'; // Only once!
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(MaterialApp(
    title: 'multimodal fall risk assessment',
    home: UserSelectionPage(),
    debugShowCheckedModeBanner: false,
  ));
}

class UserSelectionPage extends StatefulWidget {
  @override
  _UserSelectionPageState createState() => _UserSelectionPageState();
}

class _UserSelectionPageState extends State<UserSelectionPage> {
  List<String> users = [];
  List<bool> _hovering = [];

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final loadedUsers = prefs.getStringList('users') ?? [];
    setState(() {
      users = loadedUsers;
      _hovering = List<bool>.filled(users.length, false);
    });
  }

  Future<void> _addUser(String name) async {
    final prefs = await SharedPreferences.getInstance();
    users.add(name);
    await prefs.setStringList('users', users);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SurveyPage(userName: name),
      ),
    );
  }

  Future<void> _deleteUser(String name) async {
    final prefs = await SharedPreferences.getInstance();
    users.remove(name);
    await prefs.setStringList('users', users);
    await prefs.remove('$name:data');
    setState(() {
      _hovering = List<bool>.filled(users.length, false);
    });
  }

  void _selectUser(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('$name:data');
    final saved = data != null ? jsonDecode(data) : {};

    if (saved['Name'] == null ||
        saved['Age'] == null ||
        saved['Height'] == null ||
        saved['Weight'] == null ||
        saved['Sex'] == null) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => SurveyPage(userName: name)));
    } else if (saved['FallRiskAnswers'] == null) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => FallRiskPage(userName: name)));
    } else if (saved['Video_path'] == null) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => VideoPageWrapper(userName: name)));
    } else {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => SensorPageWrapper(userName: name)));
    }
  }

  void _showAddUserDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Enter Name'),
        content: TextField(controller: controller),
        actions: [
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty && !users.contains(name)) {
                _addUser(name);
              }
              Navigator.of(context).pop();
            },
            child: Text('Create'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Select or Create User')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _showAddUserDialog,
              child: Text('Create New User'),
            ),
            SizedBox(height: 20),
            Text('Or select an existing user:'),
            ...List.generate(users.length, (index) {
              final u = users[index];
              final isHovered = _hovering[index];
              return Center(
                child: MouseRegion(
                  onEnter: (_) {
                    setState(() {
                      _hovering[index] = true;
                    });
                  },
                  onExit: (_) {
                    setState(() {
                      _hovering[index] = false;
                    });
                  },
                  child: GestureDetector(
                    onTap: () => _selectUser(u),
                    child: Container(
                      padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                      decoration: BoxDecoration(
                        color: isHovered ? Colors.grey[300] : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person, color: isHovered ? Colors.blue : Colors.black),
                          SizedBox(width: 8),
                          Text(
                            u,
                            style: TextStyle(
                              color: isHovered ? Colors.blue : Colors.black,
                              fontWeight: isHovered ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          SizedBox(width: 8),
                          AnimatedOpacity(
                            opacity: isHovered ? 1.0 : 0.0,
                            duration: Duration(milliseconds: 200),
                            child: IconButton(
                              icon: Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteUser(u),
                              tooltip: 'Delete user',
                              splashRadius: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class SurveyPage extends StatefulWidget {
  final String userName;
  SurveyPage({required this.userName});

  @override
  _SurveyPageState createState() => _SurveyPageState();
}

class _SurveyPageState extends State<SurveyPage> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, String> _formData = {};

  String? sex;
  String? _sexError;

  void _saveForm() async {
    final isValid = _formKey.currentState?.validate() ?? false;

    if (sex == null) {
      setState(() {
        _sexError = 'Please select your sex';
      });
    } else {
      setState(() {
        _sexError = null;
      });
    }

    if (isValid && sex != null) {
      _formKey.currentState!.save();
      _formData['Sex'] = sex!;

      final prefs = await SharedPreferences.getInstance();
      final key = '${widget.userName}:data';
      final existingData = prefs.getString(key);
      final saved = existingData != null ? jsonDecode(existingData) : {};
      saved.addAll(_formData);
      await prefs.setString(key, jsonEncode(saved));

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => FallRiskPage(userName: widget.userName),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Survey Form"),
        leading: BackButton(
          onPressed: () {
            Navigator.pushReplacement(
                context, MaterialPageRoute(builder: (_) => UserSelectionPage()));
          },
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 200,
                  child: TextFormField(
                    decoration: InputDecoration(labelText: 'Name'),
                    onSaved: (val) => _formData['Name'] = val ?? '',
                    validator: (val) => (val == null || val.isEmpty) ? 'Required' : null,
                  ),
                ),
                SizedBox(height: 16),
                SizedBox(
                  width: 200,
                  child: TextFormField(
                    decoration: InputDecoration(labelText: 'Age (in years)'),
                    keyboardType: TextInputType.number,
                    onSaved: (val) => _formData['Age'] = val ?? '',
                    validator: (val) {
                      if (val == null || val.isEmpty) return 'Required';
                      final parsed = int.tryParse(val);
                      if (parsed == null) return 'Must be an integer';
                      if (parsed <= 0) return 'Must be positive';
                      return null;
                    },
                  ),
                ),
                SizedBox(height: 16),
                SizedBox(
                  width: 200,
                  child: TextFormField(
                    decoration: InputDecoration(labelText: 'Height (in inches)'),
                    keyboardType: TextInputType.number,
                    onSaved: (val) => _formData['Height'] = val ?? '',
                    validator: (val) {
                      if (val == null || val.isEmpty) return 'Required';
                      final parsed = int.tryParse(val);
                      if (parsed == null) return 'Must be an integer';
                      if (parsed <= 0) return 'Must be positive';
                      return null;
                    },
                  ),
                ),
                SizedBox(height: 16),
                SizedBox(
                  width: 200,
                  child: TextFormField(
                    decoration: InputDecoration(labelText: 'Weight (in pounds)'),
                    keyboardType: TextInputType.number,
                    onSaved: (val) => _formData['Weight'] = val ?? '',
                    validator: (val) {
                      if (val == null || val.isEmpty) return 'Required';
                      final parsed = int.tryParse(val);
                      if (parsed == null) return 'Must be an integer';
                      if (parsed <= 0) return 'Must be positive';
                      return null;
                    },
                  ),
                ),
                SizedBox(height: 24),
                Text("Sex:", style: TextStyle(fontSize: 16)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ChoiceChip(
                      label: Text('Male'),
                      selected: sex == 'Male',
                      onSelected: (_) {
                        setState(() {
                          sex = 'Male';
                          _sexError = null;
                        });
                      },
                    ),
                    SizedBox(width: 10),
                    ChoiceChip(
                      label: Text('Female'),
                      selected: sex == 'Female',
                      onSelected: (_) {
                        setState(() {
                          sex = 'Female';
                          _sexError = null;
                        });
                      },
                    ),
                  ],
                ),
                if (_sexError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      _sexError!,
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _saveForm,
                  child: Text('Next'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FallRiskPage extends StatefulWidget {
  final String userName;
  const FallRiskPage({required this.userName});

  @override
  _FallRiskPageState createState() => _FallRiskPageState();
}

class _FallRiskPageState extends State<FallRiskPage> {
  final List<String> questions = [
    "I have fallen in the past year.",
    "I use or have been advised to use a cane or walker to get around safely.",
    "Sometimes I feel unsteady when I am walking.",
    "I steady myself by holding onto furniture when walking at home.",
    "I need to push with my hands to stand up from a chair.",
    "I have some trouble stepping up onto a curb.",
    "I often have to rush to the toilet.",
    "I have lost some feeling in my feet.",
    "I take medicine that sometimes makes me feel light-headed or more tired than usual.",
    "I take medicine to help me sleep or improve my mood.",
    "I often feel sad or depressed.",
  ];

  Map<int, bool?> answers = {};

  bool get allAnswered =>
      answers.length == questions.length && !answers.containsValue(null);

  void _saveAndContinue() async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${widget.userName}:data';
    final data = prefs.getString(key);
    final saved = data != null ? jsonDecode(data) : {};

    saved['FallRiskAnswers'] =
        answers.map((key, value) => MapEntry(key.toString(), value));

    await prefs.setString(key, jsonEncode(saved));

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPageWrapper(userName: widget.userName),
      ),
    );
  }

  Widget _buildQuestionRow(int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${index + 1}. ${questions[index]}',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: RadioListTile<bool>(
                  title: Text('Yes'),
                  value: true,
                  groupValue: answers[index],
                  onChanged: (value) {
                    setState(() {
                      answers[index] = value;
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              Expanded(
                child: RadioListTile<bool>(
                  title: Text('No'),
                  value: false,
                  groupValue: answers[index],
                  onChanged: (value) {
                    setState(() {
                      answers[index] = value;
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Fall Risk Screening"),
        leading: BackButton(
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => SurveyPage(userName: widget.userName),
              ),
            );
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fall Risk Screening Questionnaire',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            ...List.generate(questions.length, _buildQuestionRow),
            SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: allAnswered ? _saveAndContinue : null,
                child: Text("Next"),
              ),
            ),
            SizedBox(height: 16), // Extra space at bottom
          ],
        ),
      ),
    );
  }
}

class VideoPageWrapper extends StatelessWidget {
  final String userName;
  VideoPageWrapper({required this.userName});

  @override
  Widget build(BuildContext context) {
    return VideoPage(
      userName: userName,
      onNext: () {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => SensorPageWrapper(userName: userName)));
      },
    );
  }
}

class VideoPage extends StatefulWidget {
  final String userName;
  final VoidCallback onNext;

  const VideoPage({required this.userName, required this.onNext});

  @override
  _VideoPageState createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  CameraController? _controller;
  late PoseDetector _poseDetector;
  bool _isDetecting = false;
  String? _poseInfo;
  bool _isCameraInitialized = false;
  List<Pose> _poses = [];

  @override
  void initState() {
    super.initState();
    _poseDetector = PoseDetector(options: PoseDetectorOptions());
    _initializeCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _poseDetector.close();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();
      await _controller!.startImageStream(_processCameraImage);

      setState(() {
        _isCameraInitialized = true;
      });
    } catch (e) {
      print('Camera init error: $e');
      setState(() {
        _poseInfo = 'Failed to initialize camera';
      });
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isDetecting || _controller == null) return;
    _isDetecting = true;

    try {
      // Only support YUV420 format (Android)
      if (image.format.group != ImageFormatGroup.yuv420) {
        setState(() {
          _poseInfo = 'Camera image format not supported: ${image.format.group}';
        });
        _isDetecting = false;
        return;
      }

      final camera = _controller!.description;
      final imageRotation =
          InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
              InputImageRotation.rotation0deg;

      // Concatenate all planes as-is
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: imageRotation,
          format: InputImageFormat.yuv420,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      final poses = await _poseDetector.processImage(inputImage);

      setState(() {
        _poses = poses; // Store poses for drawing
        if (poses.isNotEmpty) {
          final pose = poses.first;
          _poseInfo = 'Detected ${pose.landmarks.length} landmarks';
          print('Pose detected with ${pose.landmarks.length} landmarks');
        } else {
          _poseInfo = 'No pose detected - Point camera at a person';
        }
      });
    } catch (e) {
      print('Pose detection error: $e');
      setState(() {
        _poseInfo = 'Camera working - Pose detection disabled due to format issues';
      });
    } finally {
      _isDetecting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Live Pose Detection'),
        leading: BackButton(
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => FallRiskPage(userName: widget.userName),
              ),
            );
          },
        ),
      ),
      body: Center(
        child: !_isCameraInitialized
            ? CircularProgressIndicator()
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AspectRatio(
                      aspectRatio: 9 / 16, // Force vertical 1080p aspect ratio
                      child: Stack(
                        children: [
                          CameraPreview(_controller!),
                          // Add pose overlay
                          CustomPaint(
                            painter: PosePainter(_poses, _controller!.value.previewSize!),
                            size: Size.infinite,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 20),
                    Text(_poseInfo ?? 'Point the camera at a person'),
                    SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: widget.onNext,
                      child: Text('Next'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

// Simple PosePainter without debug prints
class PosePainter extends CustomPainter {
  final List<Pose> poses;
  final Size previewSize;

  PosePainter(this.poses, this.previewSize);

  @override
  void paint(Canvas canvas, Size size) {
    if (poses.isEmpty) return;

    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 4.0
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    for (final pose in poses) {
      // Draw landmarks as circles
      for (final landmark in pose.landmarks.values) {
        final x = landmark.x * size.width / previewSize.width;
        final y = landmark.y * size.height / previewSize.height;
        canvas.drawCircle(Offset(x, y), 4, paint);
      }

      // Draw skeleton connections
      _drawSkeleton(canvas, pose, size, linePaint);
    }
  }

  void _drawSkeleton(Canvas canvas, Pose pose, Size size, Paint paint) {
    // Define skeleton connections (body parts)
    final connections = [
      // Body
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
      [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
      [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
      [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],

      // Legs
      [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
      [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
      [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
      [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
    ];

    for (final connection in connections) {
      final start = pose.landmarks[connection[0]];
      final end = pose.landmarks[connection[1]];

      if (start != null && end != null) {
        final startX = start.x * size.width / previewSize.width;
        final startY = start.y * size.height / previewSize.height;
        final endX = end.x * size.width / previewSize.width;
        final endY = end.y * size.height / previewSize.height;

        canvas.drawLine(
          Offset(startX, startY),
          Offset(endX, endY),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class SensorPageWrapper extends StatelessWidget {
  final String userName;
  SensorPageWrapper({required this.userName});

  @override
  Widget build(BuildContext context) {
    // Placeholder for your sensor page
    return Scaffold(
      appBar: AppBar(
        title: Text('Sensor Page (Placeholder)'),
        leading: BackButton(
          onPressed: () {
            Navigator.pushReplacement(
                context, MaterialPageRoute(builder: (_) => VideoPageWrapper(userName: userName)));
          },
        ),
      ),
      body: Center(
        child: Text('Sensor Page content goes here for user $userName'),
      ),
    );
  }
}
