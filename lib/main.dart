import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'; 
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

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

    await _saveDemographicsCSV();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => FallRiskPage(userName: widget.userName),
      ),
    );
  }
}

Future<void> _saveDemographicsCSV() async {
  try {
    final weight = double.parse(_formData['Weight'] ?? '0');
    final height = double.parse(_formData['Height'] ?? '0');
    // Correct BMI calculation for kg and meters: BMI = weight(kg) / height(m)²
    final bmi = height > 0 ? (weight / (height * height)) : 0.0;
    
    final sexBinary = sex == 'Male' ? 1 : 0;
    
    final StringBuffer demographicsCSV = StringBuffer();
    demographicsCSV.writeln('Name,Age,Height_meters,Weight_kg,Sex_binary,BMI');
    demographicsCSV.writeln('${widget.userName},${_formData['Age']},${_formData['Height']},${_formData['Weight']},$sexBinary,${bmi.toStringAsFixed(2)}');
    
    final directory = await getApplicationDocumentsDirectory();
    final fileName = '${widget.userName}_demographics.csv';
    final filePath = path.join(directory.path, fileName);
    final file = File(filePath);
    
    await file.writeAsString(demographicsCSV.toString());
    
    final prefs = await SharedPreferences.getInstance();
    final key = '${widget.userName}:data';
    final existingData = prefs.getString(key);
    final saved = existingData != null ? jsonDecode(existingData) : {};
    saved['DemographicsPath'] = filePath;
    await prefs.setString(key, jsonEncode(saved));
    
    print('Demographics CSV saved to: $filePath');
    
  } catch (e) {
    print('Error saving demographics CSV: $e');
  }
}

  Future<void> _shareCSVFile() async {
    try {
      List<XFile> filesToShare = [];
      List<String> fileNames = [];

      final prefs = await SharedPreferences.getInstance();
      final key = '${widget.userName}:data';
      final data = prefs.getString(key);
      final saved = data != null ? jsonDecode(data) : {};

      final demographicsPath = saved['DemographicsPath'] as String?;
      if (demographicsPath != null && File(demographicsPath).existsSync()) {
        filesToShare.add(XFile(demographicsPath));
        fileNames.add(path.basename(demographicsPath));
      }

      final poseDataPath = saved['PoseDataPath'] as String?;
      if (poseDataPath != null && File(poseDataPath).existsSync()) {
        filesToShare.add(XFile(poseDataPath));
        fileNames.add(path.basename(poseDataPath));
      }

      final armSeparationPath = saved['ArmSeparationPath'] as String?;
      if (armSeparationPath != null && File(armSeparationPath).existsSync()) {
        filesToShare.add(XFile(armSeparationPath));
        fileNames.add(path.basename(armSeparationPath));
      }

      final handSeparationPath = saved['HandSeparationPath'] as String?;
      if (handSeparationPath != null && File(handSeparationPath).existsSync()) {
        filesToShare.add(XFile(handSeparationPath));
        fileNames.add(path.basename(handSeparationPath));
      }

      final trunkSwingPath = saved['TrunkSwingPath'] as String?;
      if (trunkSwingPath != null && File(trunkSwingPath).existsSync()) {
        filesToShare.add(XFile(trunkSwingPath));
        fileNames.add(path.basename(trunkSwingPath));
      }

      final heelSeparationPath = saved['HeelSeparationPath'] as String?;
      if (heelSeparationPath != null && File(heelSeparationPath).existsSync()) {
        filesToShare.add(XFile(heelSeparationPath));
        fileNames.add(path.basename(heelSeparationPath));
      }

      final cleansedCsvPath = saved['CleansedCsvPath'] as String?;
      if (cleansedCsvPath != null && File(cleansedCsvPath).existsSync()) {
        filesToShare.add(XFile(cleansedCsvPath));
        fileNames.add(path.basename(cleansedCsvPath));
      }

      if (filesToShare.isNotEmpty) {
        await Share.shareXFiles(
          filesToShare,
          text: 'Fall Risk Assessment data for ${widget.userName}\n\nFiles included:\n${fileNames.map((name) => '• $name').join('\n')}',
          subject: 'Fall Risk Assessment - Complete Data Package',
        );
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sharing ${filesToShare.length} CSV file(s): ${fileNames.join(', ')}')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No CSV files to share. Please record some data first.')),
        );
      }
    } catch (e) {
      print('Error sharing files: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sharing files: $e')),
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
                    decoration: InputDecoration(labelText: 'Height (in meters)'),
                    keyboardType: TextInputType.number,
                    onSaved: (val) => _formData['Height'] = val ?? '',
                    validator: (val) {
                      if (val == null || val.isEmpty) return 'Required';
                      final parsed = double.tryParse(val);
                      if (parsed == null) return 'Must be a number';
                      if (parsed <= 0) return 'Must be positive';
                      return null;
                    },
                  ),
                ),
                SizedBox(height: 16),
                SizedBox(
                  width: 200,
                  child: TextFormField(
                    decoration: InputDecoration(labelText: 'Weight (in kg)'),
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
            SizedBox(height: 16), 
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
  InputImageRotation _rotation = InputImageRotation.rotation0deg;

  bool _isRecording = false;
  bool _hasRecorded = false;
  final StringBuffer _csvData = StringBuffer();
  String? _lastSavedFilePath;
  String? _cleansedCsvPath; // Add a variable to store cleansed CSV path
  
  DateTime? _recordingStartTime;
  Duration _recordingDuration = Duration.zero;
  Timer? _timer;

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
    _timer?.cancel(); 
    super.dispose();
  }

  void _startTimer() {
    _recordingStartTime = DateTime.now();
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (_isRecording && _recordingStartTime != null && mounted) {
        setState(() {
          _recordingDuration = DateTime.now().difference(_recordingStartTime!);
        });
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
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

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      print('Camera init error: $e');
      if (mounted) {
        setState(() {
          _poseInfo = 'Failed to initialize camera: $e';
        });
      }
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isDetecting || _controller == null || !mounted) return;
    _isDetecting = true;

    try {
      if (image.format.group != ImageFormatGroup.yuv420) {
        if (mounted) {
          setState(() {
            _poseInfo = 'Camera image format not supported: ${image.format.group}';
          });
        }
        _isDetecting = false;
        return;
      }

      final camera = _controller!.description;
      final imageRotation =
          InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
              InputImageRotation.rotation0deg;

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

      if (_isRecording && poses.isNotEmpty) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        for (final pose in poses) {
          for (final landmark in pose.landmarks.values) {
            final row = [
              timestamp,
              landmark.type.name,
              landmark.x,
              landmark.y,
              landmark.z,
              landmark.likelihood,
            ];
            _csvData.writeln(row.join(','));
          }
        }
      }

      if (mounted) {
        setState(() {
          _poses = poses;
          _rotation = imageRotation;
          if (poses.isNotEmpty) {
            final pose = poses.first;
            if (_isRecording) {
              _poseInfo = 'Recording... ${pose.landmarks.length} landmarks detected';
            } else {
              _poseInfo = 'Detected ${pose.landmarks.length} landmarks';
            }
          } else {
            if (_isRecording) {
              _poseInfo = 'Recording... No pose detected';
            } else {
              _poseInfo = 'No pose detected - Point camera at a person';
            }
          }
        });
      }
    } catch (e) {
      print('Pose detection error: $e');
      if (mounted) {
        setState(() {
          _poseInfo = 'Pose detection error: $e';
        });
      }
    } finally {
      _isDetecting = false;
    }
  }

  Future<void> _processPoseData(String csvFilePath) async {
    try {
      if (mounted) {
        setState(() {
          _poseInfo = 'Processing pose data...';
        });
      }

      final originalFile = File(csvFilePath);
      if (!originalFile.existsSync()) {
        throw Exception('Original CSV file not found');
      }

      final csvContent = await originalFile.readAsString();
      final lines = csvContent.split('\n');
      
      final List<Map<String, dynamic>> rawData = [];
      
      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        
        final parts = line.split(',');
        if (parts.length >= 6) {
          rawData.add({
            'timestamp': parts[0],
            'landmark_type': parts[1],
            'x': parts[2],
            'y': parts[3], 
            'z': parts[4],
            'likelihood': parts[5],
          });
        }
      }

      final Map<String, List<Map<String, dynamic>>> groupedData = {};
      for (final row in rawData) {
        final timestamp = row['timestamp'];
        if (!groupedData.containsKey(timestamp)) {
          groupedData[timestamp] = [];
        }
        groupedData[timestamp]!.add(row);
      }

      final jointNames = [
        'Nose', 'Left Eye Inner', 'Left Eye', 'Left Eye Outer', 'Right Eye Inner', 'Right Eye', 'Right Eye Outer',
        'Left Ear', 'Right Ear', 'Mouth Left', 'Mouth Right', 'Left Shoulder', 'Right Shoulder',
        'Left Elbow', 'Right Elbow', 'Left Wrist', 'Right Wrist', 'Left Pinky', 'Right Pinky',
        'Left Index', 'Right Index', 'Left Thumb', 'Right Thumb', 'Left Hip', 'Right Hip',
        'Left Knee', 'Right Knee', 'Left Ankle', 'Right Ankle', 'Left Heel', 'Right Heel',
        'Left Foot Index', 'Right Foot Index'
      ];

      final Map<String, String> mediapipeToHeader = {
        'nose': 'Nose',
        'leftEyeInner': 'Left Eye Inner',
        'leftEye': 'Left Eye', 
        'leftEyeOuter': 'Left Eye Outer',
        'rightEyeInner': 'Right Eye Inner',
        'rightEye': 'Right Eye',
        'rightEyeOuter': 'Right Eye Outer',
        'leftEar': 'Left Ear',
        'rightEar': 'Right Ear',
        'leftMouth': 'Mouth Left',
        'rightMouth': 'Mouth Right',
        'leftShoulder': 'Left Shoulder',
        'rightShoulder': 'Right Shoulder',
        'leftElbow': 'Left Elbow',
        'rightElbow': 'Right Elbow',
        'leftWrist': 'Left Wrist',
        'rightWrist': 'Right Wrist',
        'leftPinky': 'Left Pinky',
        'rightPinky': 'Right Pinky',
        'leftIndex': 'Left Index',
        'rightIndex': 'Right Index',
        'leftThumb': 'Left Thumb',
        'rightThumb': 'Right Thumb',
        'leftHip': 'Left Hip',
        'rightHip': 'Right Hip',
        'leftKnee': 'Left Knee',
        'rightKnee': 'Right Knee',
        'leftAnkle': 'Left Ankle',
        'rightAnkle': 'Right Ankle',
        'leftHeel': 'Left Heel',
        'rightHeel': 'Right Heel',
        'leftFootIndex': 'Left Foot Index',
        'rightFootIndex': 'Right Foot Index'
      };

      final StringBuffer restructuredData = StringBuffer();
      
      restructuredData.writeln('Frame Number,${jointNames.join(',')}');
      
      final timestamps = groupedData.keys.toList()..sort();
      
      for (int frameIdx = 0; frameIdx < timestamps.length; frameIdx++) {
        final timestamp = timestamps[frameIdx];
        final timestampData = groupedData[timestamp]!;
        
        final Map<String, double> xCoords = {};
        final Map<String, double> yCoords = {};
        final Map<String, double> zCoords = {};
        
        for (final joint in jointNames) {
          xCoords[joint] = double.nan;
          yCoords[joint] = double.nan;
          zCoords[joint] = double.nan;
        }
        
        for (final row in timestampData) {
          final originalJointName = row['landmark_type'];
          if (mediapipeToHeader.containsKey(originalJointName)) {
            final headerName = mediapipeToHeader[originalJointName]!;
            xCoords[headerName] = double.tryParse(row['x']) ?? double.nan;
            yCoords[headerName] = double.tryParse(row['y']) ?? double.nan;
            zCoords[headerName] = double.tryParse(row['z']) ?? double.nan;
          }
        }
        
        final List<String> xRow = [frameIdx.toString()];
        final List<String> yRow = [frameIdx.toString()];
        final List<String> zRow = [frameIdx.toString()];
        
        for (final joint in jointNames) {
          xRow.add(xCoords[joint]!.isNaN ? '' : xCoords[joint].toString());
          yRow.add(yCoords[joint]!.isNaN ? '' : yCoords[joint].toString());
          zRow.add(zCoords[joint]!.isNaN ? '' : zCoords[joint].toString());
        }
        
        restructuredData.writeln(xRow.join(','));
        restructuredData.writeln(yRow.join(','));
        restructuredData.writeln(zRow.join(','));
      }

      final directory = await getApplicationDocumentsDirectory();
      final originalFileName = path.basename(csvFilePath);
      final nameWithoutExtension = path.basenameWithoutExtension(originalFileName);
      final newFileName = '${nameWithoutExtension}_restructured.csv';
      final newFilePath = path.join(directory.path, newFileName);
      
      final newFile = File(newFilePath);
      await newFile.writeAsString(restructuredData.toString());
      
      await originalFile.delete();
      
      _lastSavedFilePath = newFilePath;
      
      final prefs = await SharedPreferences.getInstance();
      final key = '${widget.userName}:data';
      final data = prefs.getString(key);
      final saved = data != null ? jsonDecode(data) : {};
      saved['PoseDataPath'] = newFilePath;
      await prefs.setString(key, jsonEncode(saved));
      
      if (mounted) {
        setState(() {
          _poseInfo = 'Pose data processed and restructured!';
        });
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pose data restructured successfully: $newFileName')),
      );
      
    } catch (e) {
      print('Error processing pose data: $e');
      if (mounted) {
        setState(() {
          _poseInfo = 'Error processing pose data: $e';
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error processing pose data: $e')),
      );
    }
  }
  
  Future<void> _calculateArmSeparation(String restructuredFilePath) async {
    try {
      if (mounted) {
        setState(() {
          _poseInfo = 'Calculating arm separation...';
        });
      }

      final file = File(restructuredFilePath);
      if (!file.existsSync()) {
        throw Exception('Restructured CSV file not found');
      }

      final csvContent = await file.readAsString();
      final lines = csvContent.split('\n').where((line) => line.trim().isNotEmpty).toList();
      
      if (lines.length < 2) {
        throw Exception('Not enough data to calculate arm separation');
      }

      final headers = lines[0].split(',');
      final leftShoulderIdx = headers.indexOf('Left Shoulder');
      final rightShoulderIdx = headers.indexOf('Right Shoulder');
      final leftElbowIdx = headers.indexOf('Left Elbow');
      final rightElbowIdx = headers.indexOf('Right Elbow');
      final leftHipIdx = headers.indexOf('Left Hip');
      final rightHipIdx = headers.indexOf('Right Hip');

      if (leftShoulderIdx == -1 || rightShoulderIdx == -1 || 
          leftElbowIdx == -1 || rightElbowIdx == -1 ||
          leftHipIdx == -1 || rightHipIdx == -1) {
        throw Exception('Required joint columns not found in CSV');
      }

      final Map<int, List<List<String>>> frameGroups = {};
      
      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        
        final parts = line.split(',');
        if (parts.isEmpty) continue;
        
        final frameNumber = int.tryParse(parts[0]);
        if (frameNumber == null) continue;
        
        if (!frameGroups.containsKey(frameNumber)) {
          frameGroups[frameNumber] = [];
        }
        frameGroups[frameNumber]!.add(parts);
      }

      final List<Map<String, double>> armSeparationData = [];
      
      for (final frameNumber in frameGroups.keys.toList()..sort()) {
        final frameData = frameGroups[frameNumber]!;
        
        if (frameData.length == 3) { 
          try {
            final leftShoulderX = double.tryParse(frameData[0][leftShoulderIdx]) ?? 0.0;
            final leftShoulderY = double.tryParse(frameData[1][leftShoulderIdx]) ?? 0.0;
            final leftShoulderZ = double.tryParse(frameData[2][leftShoulderIdx]) ?? 0.0;
            final leftShoulder = [leftShoulderX, leftShoulderY, leftShoulderZ];

            final rightShoulderX = double.tryParse(frameData[0][rightShoulderIdx]) ?? 0.0;
            final rightShoulderY = double.tryParse(frameData[1][rightShoulderIdx]) ?? 0.0;
            final rightShoulderZ = double.tryParse(frameData[2][rightShoulderIdx]) ?? 0.0;
            final rightShoulder = [rightShoulderX, rightShoulderY, rightShoulderZ];

            final leftElbowX = double.tryParse(frameData[0][leftElbowIdx]) ?? 0.0;
            final leftElbowY = double.tryParse(frameData[1][leftElbowIdx]) ?? 0.0;
            final leftElbowZ = double.tryParse(frameData[2][leftElbowIdx]) ?? 0.0;
            final leftElbow = [leftElbowX, leftElbowY, leftElbowZ];

            final rightElbowX = double.tryParse(frameData[0][rightElbowIdx]) ?? 0.0;
            final rightElbowY = double.tryParse(frameData[1][rightElbowIdx]) ?? 0.0;
            final rightElbowZ = double.tryParse(frameData[2][rightElbowIdx]) ?? 0.0;
            final rightElbow = [rightElbowX, rightElbowY, rightElbowZ];

            final leftHipX = double.tryParse(frameData[0][leftHipIdx]) ?? 0.0;
            final leftHipY = double.tryParse(frameData[1][leftHipIdx]) ?? 0.0;
            final leftHipZ = double.tryParse(frameData[2][leftHipIdx]) ?? 0.0;
            final leftHip = [leftHipX, leftHipY, leftHipZ];

            final rightHipX = double.tryParse(frameData[0][rightHipIdx]) ?? 0.0;
            final rightHipY = double.tryParse(frameData[1][rightHipIdx]) ?? 0.0;
            final rightHipZ = double.tryParse(frameData[2][rightHipIdx]) ?? 0.0;
            final rightHip = [rightHipX, rightHipY, rightHipZ];

            final separationLeft = _calculateAngle(leftElbow, leftShoulder, leftHip);
            final separationRight = _calculateAngle(rightElbow, rightShoulder, rightHip);

            armSeparationData.add({
              'separation_left': separationLeft,
              'separation_right': separationRight,
            });
            
          } catch (e) {
            print('Error processing frame $frameNumber: $e');
            armSeparationData.add({
              'separation_left': 0.0,
              'separation_right': 0.0,
            });
          }
        }
      }

      final StringBuffer armSeparationCsv = StringBuffer();
      armSeparationCsv.writeln('separation_left,separation_right');
      
      for (final data in armSeparationData) {
        armSeparationCsv.writeln('${data['separation_left']},${data['separation_right']}');
      }

      final directory = await getApplicationDocumentsDirectory();
      final armSeparationFileName = '${widget.userName}_arm_separation.csv';
      final armSeparationFilePath = path.join(directory.path, armSeparationFileName);
      final armSeparationFile = File(armSeparationFilePath);
      
      await armSeparationFile.writeAsString(armSeparationCsv.toString());

      final prefs = await SharedPreferences.getInstance();
      final key = '${widget.userName}:data';
      final data = prefs.getString(key);
      final saved = data != null ? jsonDecode(data) : {};
      saved['ArmSeparationPath'] = armSeparationFilePath;
      await prefs.setString(key, jsonEncode(saved));

      if (mounted) {
        setState(() {
          _poseInfo = 'Arm separation calculated successfully!';
        });
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Arm separation data saved: $armSeparationFileName')),
      );
      
    } catch (e) {
      print('Error calculating arm separation: $e');
      if (mounted) {
        setState(() {
          _poseInfo = 'Error calculating arm separation: $e';
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error calculating arm separation: $e')),
      );
    }
  }

  Future<void> _calculateHandSeparation(String restructuredFilePath) async {
    try {
      if (mounted) {
        setState(() {
          _poseInfo = 'Calculating hand separation...';
        });
      }

      final file = File(restructuredFilePath);
      if (!file.existsSync()) {
        throw Exception('Restructured CSV file not found');
      }

      final csvContent = await file.readAsString();
      final lines = csvContent.split('\n').where((line) => line.trim().isNotEmpty).toList();
      
      if (lines.length < 2) {
        throw Exception('Not enough data to calculate hand separation');
      }

      final headers = lines[0].split(',');
      final leftWristIdx = headers.indexOf('Left Wrist');
      final rightWristIdx = headers.indexOf('Right Wrist');
      final leftElbowIdx = headers.indexOf('Left Elbow');
      final rightElbowIdx = headers.indexOf('Right Elbow');
      final leftShoulderIdx = headers.indexOf('Left Shoulder');
      final rightShoulderIdx = headers.indexOf('Right Shoulder');

      if (leftWristIdx == -1 || rightWristIdx == -1 || 
          leftElbowIdx == -1 || rightElbowIdx == -1 ||
          leftShoulderIdx == -1 || rightShoulderIdx == -1) {
        throw Exception('Required joint columns not found in CSV');
      }

      final Map<int, List<List<String>>> frameGroups = {};
      
      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        
        final parts = line.split(',');
        if (parts.isEmpty) continue;
        
        final frameNumber = int.tryParse(parts[0]);
        if (frameNumber == null) continue;
        
        if (!frameGroups.containsKey(frameNumber)) {
          frameGroups[frameNumber] = [];
        }
        frameGroups[frameNumber]!.add(parts);
      }

      final List<Map<String, double>> handSeparationData = [];
      
      for (final frameNumber in frameGroups.keys.toList()..sort()) {
        final frameData = frameGroups[frameNumber]!;
        
        if (frameData.length == 3) { 
          try {
            final leftWristX = double.tryParse(frameData[0][leftWristIdx]) ?? 0.0;
            final leftWristY = double.tryParse(frameData[1][leftWristIdx]) ?? 0.0;
            final leftWristZ = double.tryParse(frameData[2][leftWristIdx]) ?? 0.0;
            final leftWrist = [leftWristX, leftWristY, leftWristZ];

            final rightWristX = double.tryParse(frameData[0][rightWristIdx]) ?? 0.0;
            final rightWristY = double.tryParse(frameData[1][rightWristIdx]) ?? 0.0;
            final rightWristZ = double.tryParse(frameData[2][rightWristIdx]) ?? 0.0;
            final rightWrist = [rightWristX, rightWristY, rightWristZ];

            final leftElbowX = double.tryParse(frameData[0][leftElbowIdx]) ?? 0.0;
            final leftElbowY = double.tryParse(frameData[1][leftElbowIdx]) ?? 0.0;
            final leftElbowZ = double.tryParse(frameData[2][leftElbowIdx]) ?? 0.0;
            final leftElbow = [leftElbowX, leftElbowY, leftElbowZ];

            final rightElbowX = double.tryParse(frameData[0][rightElbowIdx]) ?? 0.0;
            final rightElbowY = double.tryParse(frameData[1][rightElbowIdx]) ?? 0.0;
            final rightElbowZ = double.tryParse(frameData[2][rightElbowIdx]) ?? 0.0;
            final rightElbow = [rightElbowX, rightElbowY, rightElbowZ];

            final leftShoulderX = double.tryParse(frameData[0][leftShoulderIdx]) ?? 0.0;
            final leftShoulderY = double.tryParse(frameData[1][leftShoulderIdx]) ?? 0.0;
            final leftShoulderZ = double.tryParse(frameData[2][leftShoulderIdx]) ?? 0.0;
            final leftShoulder = [leftShoulderX, leftShoulderY, leftShoulderZ];

            final rightShoulderX = double.tryParse(frameData[0][rightShoulderIdx]) ?? 0.0;
            final rightShoulderY = double.tryParse(frameData[1][rightShoulderIdx]) ?? 0.0;
            final rightShoulderZ = double.tryParse(frameData[2][rightShoulderIdx]) ?? 0.0;
            final rightShoulder = [rightShoulderX, rightShoulderY, rightShoulderZ];

            final separationLeft = _calculateAngle(leftWrist, leftElbow, leftShoulder);
            final separationRight = _calculateAngle(rightWrist, rightElbow, rightShoulder);

            handSeparationData.add({
              'hand_separation_left': separationLeft,
              'hand_separation_right': separationRight,
            });
            
          } catch (e) {
            print('Error processing frame $frameNumber: $e');
            handSeparationData.add({
              'hand_separation_left': 0.0,
              'hand_separation_right': 0.0,
            });
          }
        }
      }

      final StringBuffer handSeparationCsv = StringBuffer();
      handSeparationCsv.writeln('hand_separation_left,hand_separation_right');
      
      for (final data in handSeparationData) {
        handSeparationCsv.writeln('${data['hand_separation_left']},${data['hand_separation_right']}');
      }

      final directory = await getApplicationDocumentsDirectory();
      final handSeparationFileName = '${widget.userName}_hand_separation.csv';
      final handSeparationFilePath = path.join(directory.path, handSeparationFileName);
      final handSeparationFile = File(handSeparationFilePath);
      
      await handSeparationFile.writeAsString(handSeparationCsv.toString());

      final prefs = await SharedPreferences.getInstance();
      final key = '${widget.userName}:data';
      final data = prefs.getString(key);
      final saved = data != null ? jsonDecode(data) : {};
      saved['HandSeparationPath'] = handSeparationFilePath;
      await prefs.setString(key, jsonEncode(saved));

      if (mounted) {
        setState(() {
          _poseInfo = 'Hand separation calculated successfully!';
        });
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hand separation data saved: $handSeparationFileName')),
      );
      
    } catch (e) {
      print('Error calculating hand separation: $e');
      if (mounted) {
        setState(() {
          _poseInfo = 'Error calculating hand separation: $e';
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error calculating hand separation: $e')),
      );
    }
  }

  Future<void> _calculateTrunkSwing(String restructuredFilePath) async {
    try {
      if (mounted) {
        setState(() {
          _poseInfo = 'Calculating trunk swing...';
        });
      }

      final file = File(restructuredFilePath);
      if (!file.existsSync()) {
        throw Exception('Restructured CSV file not found');
      }

      final csvContent = await file.readAsString();
      final lines = csvContent.split('\n').where((line) => line.trim().isNotEmpty).toList();
      
      if (lines.length < 2) {
        throw Exception('Not enough data to calculate trunk swing');
      }

      final headers = lines[0].split(',');
      final leftShoulderIdx = headers.indexOf('Left Shoulder');
      final rightShoulderIdx = headers.indexOf('Right Shoulder');

      if (leftShoulderIdx == -1 || rightShoulderIdx == -1) {
        throw Exception('Required shoulder columns not found in CSV');
      }

      final Map<int, List<List<String>>> frameGroups = {};
      
      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        
        final parts = line.split(',');
        if (parts.isEmpty) continue;
        
        final frameNumber = int.tryParse(parts[0]);
        if (frameNumber == null) continue;
        
        if (!frameGroups.containsKey(frameNumber)) {
          frameGroups[frameNumber] = [];
        }
        frameGroups[frameNumber]!.add(parts);
      }

      final List<Map<String, double>> trunkSwingData = [];
      
      for (final frameNumber in frameGroups.keys.toList()..sort()) {
        final frameData = frameGroups[frameNumber]!;
        
        if (frameData.length == 3) { 
          try {
            final leftShoulderX = double.tryParse(frameData[0][leftShoulderIdx]) ?? 0.0;
            final leftShoulderY = double.tryParse(frameData[1][leftShoulderIdx]) ?? 0.0;
            final leftShoulderZ = double.tryParse(frameData[2][leftShoulderIdx]) ?? 0.0;
            final leftShoulder = [leftShoulderX, leftShoulderY, leftShoulderZ];

            final rightShoulderX = double.tryParse(frameData[0][rightShoulderIdx]) ?? 0.0;
            final rightShoulderY = double.tryParse(frameData[1][rightShoulderIdx]) ?? 0.0;
            final rightShoulderZ = double.tryParse(frameData[2][rightShoulderIdx]) ?? 0.0;
            final rightShoulder = [rightShoulderX, rightShoulderY, rightShoulderZ];

            List<double> flat;
            if (leftShoulder[1] > rightShoulder[1]) {
              flat = [0, leftShoulder[1], leftShoulder[1]];
            } else {
              flat = [0, rightShoulder[1], rightShoulder[1]];
            }

            final trunkSwing = _calculateAngle(leftShoulder, rightShoulder, flat);

            trunkSwingData.add({
              'trunk_swing': trunkSwing,
            });
            
          } catch (e) {
            print('Error processing frame $frameNumber: $e');
            trunkSwingData.add({
              'trunk_swing': 0.0,
            });
          }
        }
      }

      final StringBuffer trunkSwingCsv = StringBuffer();
      trunkSwingCsv.writeln('trunk_swing');
      
      for (final data in trunkSwingData) {
        trunkSwingCsv.writeln('${data['trunk_swing']}');
      }

      final directory = await getApplicationDocumentsDirectory();
      final trunkSwingFileName = '${widget.userName}_trunk_swing.csv';
      final trunkSwingFilePath = path.join(directory.path, trunkSwingFileName);
      final trunkSwingFile = File(trunkSwingFilePath);
      
      await trunkSwingFile.writeAsString(trunkSwingCsv.toString());

      final prefs = await SharedPreferences.getInstance();
      final key = '${widget.userName}:data';
      final data = prefs.getString(key);
      final saved = data != null ? jsonDecode(data) : {};
      saved['TrunkSwingPath'] = trunkSwingFilePath;
      await prefs.setString(key, jsonEncode(saved));

      if (mounted) {
        setState(() {
          _poseInfo = 'Trunk swing calculated successfully!';
        });
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Trunk swing data saved: $trunkSwingFileName')),
      );
      
    } catch (e) {
      print('Error calculating trunk swing: $e');
      if (mounted) {
        setState(() {
          _poseInfo = 'Error calculating trunk swing: $e';
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error calculating trunk swing: $e')),
      );
    }
  }

  Future<void> _calculateHeelSeparation(String restructuredFilePath) async {
    try {
      if (mounted) {
        setState(() {
          _poseInfo = 'Calculating heel separation...';
        });
      }

      final file = File(restructuredFilePath);
      if (!file.existsSync()) {
        throw Exception('Restructured CSV file not found');
      }

      final csvContent = await file.readAsString();
      final lines = csvContent.split('\n').where((line) => line.trim().isNotEmpty).toList();
      
      if (lines.length < 2) {
        throw Exception('Not enough data to calculate heel separation');
      }

      final headers = lines[0].split(',');
      final leftHeelIdx = headers.indexOf('Left Heel');
      final rightHeelIdx = headers.indexOf('Right Heel');
      final leftAnkleIdx = headers.indexOf('Left Ankle');
      final rightAnkleIdx = headers.indexOf('Right Ankle');
      final leftKneeIdx = headers.indexOf('Left Knee');
      final rightKneeIdx = headers.indexOf('Right Knee');

      if (leftHeelIdx == -1 || rightHeelIdx == -1 || 
          leftAnkleIdx == -1 || rightAnkleIdx == -1 ||
          leftKneeIdx == -1 || rightKneeIdx == -1) {
        throw Exception('Required joint columns not found in CSV');
      }

      final Map<int, List<List<String>>> frameGroups = {};
      
      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        
        final parts = line.split(',');
        if (parts.isEmpty) continue;
        
        final frameNumber = int.tryParse(parts[0]);
        if (frameNumber == null) continue;
        
        if (!frameGroups.containsKey(frameNumber)) {
          frameGroups[frameNumber] = [];
        }
        frameGroups[frameNumber]!.add(parts);
      }

      final List<Map<String, double>> heelSeparationData = [];
      
      for (final frameNumber in frameGroups.keys.toList()..sort()) {
        final frameData = frameGroups[frameNumber]!;
        
        if (frameData.length == 3) { 
          try {
            final leftHeelX = double.tryParse(frameData[0][leftHeelIdx]) ?? 0.0;
            final leftHeelY = double.tryParse(frameData[1][leftHeelIdx]) ?? 0.0;
            final leftHeelZ = double.tryParse(frameData[2][leftHeelIdx]) ?? 0.0;
            final leftHeel = [leftHeelX, leftHeelY, leftHeelZ];

            final rightHeelX = double.tryParse(frameData[0][rightHeelIdx]) ?? 0.0;
            final rightHeelY = double.tryParse(frameData[1][rightHeelIdx]) ?? 0.0;
            final rightHeelZ = double.tryParse(frameData[2][rightHeelIdx]) ?? 0.0;
            final rightHeel = [rightHeelX, rightHeelY, rightHeelZ];

            final leftAnkleX = double.tryParse(frameData[0][leftAnkleIdx]) ?? 0.0;
            final leftAnkleY = double.tryParse(frameData[1][leftAnkleIdx]) ?? 0.0;
            final leftAnkleZ = double.tryParse(frameData[2][leftAnkleIdx]) ?? 0.0;
            final leftAnkle = [leftAnkleX, leftAnkleY, leftAnkleZ];

            final rightAnkleX = double.tryParse(frameData[0][rightAnkleIdx]) ?? 0.0;
            final rightAnkleY = double.tryParse(frameData[1][rightAnkleIdx]) ?? 0.0;
            final rightAnkleZ = double.tryParse(frameData[2][rightAnkleIdx]) ?? 0.0;
            final rightAnkle = [rightAnkleX, rightAnkleY, rightAnkleZ];

            final leftKneeX = double.tryParse(frameData[0][leftKneeIdx]) ?? 0.0;
            final leftKneeY = double.tryParse(frameData[1][leftKneeIdx]) ?? 0.0;
            final leftKneeZ = double.tryParse(frameData[2][leftKneeIdx]) ?? 0.0;
            final leftKnee = [leftKneeX, leftKneeY, leftKneeZ];

            final rightKneeX = double.tryParse(frameData[0][rightKneeIdx]) ?? 0.0;
            final rightKneeY = double.tryParse(frameData[1][rightKneeIdx]) ?? 0.0;
            final rightKneeZ = double.tryParse(frameData[2][rightKneeIdx]) ?? 0.0;
            final rightKnee = [rightKneeX, rightKneeY, rightKneeZ];

            final separationLeft = _calculateAngle(leftHeel, leftAnkle, leftKnee);
            final separationRight = _calculateAngle(rightHeel, rightAnkle, rightKnee);

            heelSeparationData.add({
              'heel_separation_left': separationLeft,
              'heel_separation_right': separationRight,
            });
            
          } catch (e) {
            print('Error processing frame $frameNumber: $e');
            heelSeparationData.add({
              'heel_separation_left': 0.0,
              'heel_separation_right': 0.0,
            });
          }
        }
      }

      final StringBuffer heelSeparationCsv = StringBuffer();
      heelSeparationCsv.writeln('heel_separation_left,heel_separation_right');
      
      for (final data in heelSeparationData) {
        heelSeparationCsv.writeln('${data['heel_separation_left']},${data['heel_separation_right']}');
      }

      final directory = await getApplicationDocumentsDirectory();
      final heelSeparationFileName = '${widget.userName}_heel_separation.csv';
      final heelSeparationFilePath = path.join(directory.path, heelSeparationFileName);
      final heelSeparationFile = File(heelSeparationFilePath);
      
      await heelSeparationFile.writeAsString(heelSeparationCsv.toString());

      final prefs = await SharedPreferences.getInstance();
      final key = '${widget.userName}:data';
      final data = prefs.getString(key);
      final saved = data != null ? jsonDecode(data) : {};
      saved['HeelSeparationPath'] = heelSeparationFilePath;
      await prefs.setString(key, jsonEncode(saved));

      if (mounted) {
        setState(() {
          _poseInfo = 'Heel separation calculated successfully!';
        });
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Heel separation data saved: $heelSeparationFileName')),
      );
      
    } catch (e) {
      print('Error calculating heel separation: $e');
      if (mounted) {
        setState(() {
          _poseInfo = 'Error calculating heel separation: $e';
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error calculating heel separation: $e')),
      );
    }
  }

  Future<void> _runDataCleansingScript() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${widget.userName}:data';
      final data = prefs.getString(key);
      final saved = data != null ? jsonDecode(data) : {};

      final demographicsPath = saved['DemographicsPath'] as String?;
      final armSeparationPath = saved['ArmSeparationPath'] as String?;
      final handSeparationPath = saved['HandSeparationPath'] as String?;
      final trunkSwingPath = saved['TrunkSwingPath'] as String?;
      final heelSeparationPath = saved['HeelSeparationPath'] as String?;

      // Only proceed if all 5 files exist (demographics + 4 gait metrics)
      if ([demographicsPath, armSeparationPath, handSeparationPath, trunkSwingPath, heelSeparationPath].any((p) => p == null || !File(p!).existsSync())) {
        if (mounted) {
          setState(() {
            _poseInfo = 'Not all CSV files are available for cleansing.';
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _poseInfo = 'Processing and cleansing data...';
        });
      }

      // Process demographics data
      final demographicsFile = File(demographicsPath!);
      final demographicsContent = await demographicsFile.readAsString();
      final demographicsLines = demographicsContent.split('\n');
      final demographicsHeaders = demographicsLines[0].split(',');
      final demographicsValues = demographicsLines[1].split(',');
      
      Map<String, dynamic> demographicsData = {};
      for (int i = 0; i < demographicsHeaders.length && i < demographicsValues.length; i++) {
        demographicsData[demographicsHeaders[i].trim()] = demographicsValues[i].trim();
      }

      // Process trunk swing data
      final trunkSwingFile = File(trunkSwingPath!);
      final trunkSwingContent = await trunkSwingFile.readAsString();
      final trunkSwingLines = trunkSwingContent.split('\n').where((line) => line.trim().isNotEmpty).toList();
      List<double> trunkSwingValues = [];
      for (int i = 1; i < trunkSwingLines.length; i++) {
        final value = double.tryParse(trunkSwingLines[i].trim());
        if (value != null) trunkSwingValues.add(value);
      }
      final trunkSwingMean = trunkSwingValues.isNotEmpty ? trunkSwingValues.reduce((a, b) => a + b) / trunkSwingValues.length : 0.0;
      final trunkSwingStd = trunkSwingValues.isNotEmpty ? _calculateStandardDeviation(trunkSwingValues) : 0.0;

      // Process heel separation data (Step Width)
      final heelSeparationFile = File(heelSeparationPath!);
      final heelSeparationContent = await heelSeparationFile.readAsString();
      final heelSeparationLines = heelSeparationContent.split('\n').where((line) => line.trim().isNotEmpty).toList();
      List<double> stepWidthValues = [];
      for (int i = 1; i < heelSeparationLines.length; i++) {
        final parts = heelSeparationLines[i].split(',');
        if (parts.length >= 2) {
          final leftValue = double.tryParse(parts[0].trim());
          final rightValue = double.tryParse(parts[1].trim());
          if (leftValue != null && rightValue != null) {
            // Calculate step width as the average of left and right heel separation
            stepWidthValues.add((leftValue + rightValue) / 2.0);
          }
        }
      }
      final stepWidthMean = stepWidthValues.isNotEmpty ? stepWidthValues.reduce((a, b) => a + b) / stepWidthValues.length : 0.0;
      final stepWidthStd = stepWidthValues.isNotEmpty ? _calculateStandardDeviation(stepWidthValues) : 0.0;

      // Process arm separation data
      final armSeparationFile = File(armSeparationPath!);
      final armSeparationContent = await armSeparationFile.readAsString();
      final armSeparationLines = armSeparationContent.split('\n').where((line) => line.trim().isNotEmpty).toList();
      List<double> armLeftValues = [];
      List<double> armRightValues = [];
      for (int i = 1; i < armSeparationLines.length; i++) {
        final parts = armSeparationLines[i].split(',');
        if (parts.length >= 2) {
          final leftValue = double.tryParse(parts[0].trim());
          final rightValue = double.tryParse(parts[1].trim());
          if (leftValue != null) armLeftValues.add(leftValue);
          if (rightValue != null) armRightValues.add(rightValue);
        }
      }
      final armLeftMean = armLeftValues.isNotEmpty ? armLeftValues.reduce((a, b) => a + b) / armLeftValues.length : 0.0;
      final armLeftStd = armLeftValues.isNotEmpty ? _calculateStandardDeviation(armLeftValues) : 0.0;
      final armRightMean = armRightValues.isNotEmpty ? armRightValues.reduce((a, b) => a + b) / armRightValues.length : 0.0;
      final armRightStd = armRightValues.isNotEmpty ? _calculateStandardDeviation(armRightValues) : 0.0;

      // Process hand separation data
      final handSeparationFile = File(handSeparationPath!);
      final handSeparationContent = await handSeparationFile.readAsString();
      final handSeparationLines = handSeparationContent.split('\n').where((line) => line.trim().isNotEmpty).toList();
      List<double> handValues = [];
      for (int i = 1; i < handSeparationLines.length; i++) {
        final parts = handSeparationLines[i].split(',');
        if (parts.length >= 2) {
          final leftValue = double.tryParse(parts[0].trim());
          final rightValue = double.tryParse(parts[1].trim());
          if (leftValue != null && rightValue != null) {
            // Calculate hand separation as the average of left and right
            handValues.add((leftValue + rightValue) / 2.0);
          }
        }
      }
      final handSeparationMean = handValues.isNotEmpty ? handValues.reduce((a, b) => a + b) / handValues.length : 0.0;

      // Create cleansed data with specified format
      final StringBuffer cleansedCsv = StringBuffer();
      cleansedCsv.writeln('Part_id,age,sex,height,weight,BMI,Step Width mean,Step Width std,Trunk Swing mean,Trunk Swing std,Arm Separation Left mean,Arm Separation Right mean,Arm Separation Left std,Arm Separation Right std,Hand Separation mean');
      
      // Convert sex to text format (1 = M, 0 = F)
      final sexText = demographicsData['Sex_binary'] == '1' ? 'M' : 'F';
      
      cleansedCsv.write('${demographicsData['Name']},');
      cleansedCsv.write('${demographicsData['Age']},');
      cleansedCsv.write('$sexText,');
      cleansedCsv.write('${demographicsData['Height_meters']},');
      cleansedCsv.write('${demographicsData['Weight_kg']},');
      cleansedCsv.write('${demographicsData['BMI']},');
      cleansedCsv.write('${stepWidthMean.toStringAsFixed(2)},');
      cleansedCsv.write('${stepWidthStd.toStringAsFixed(2)},');
      cleansedCsv.write('${trunkSwingMean.toStringAsFixed(2)},');
      cleansedCsv.write('${trunkSwingStd.toStringAsFixed(2)},');
      cleansedCsv.write('${armLeftMean.toStringAsFixed(2)},');
      cleansedCsv.write('${armRightMean.toStringAsFixed(2)},');
      cleansedCsv.write('${armLeftStd.toStringAsFixed(2)},');
      cleansedCsv.write('${armRightStd.toStringAsFixed(2)},');
      cleansedCsv.writeln('${handSeparationMean.toStringAsFixed(2)}');

      // Save cleansed data
      final directory = await getApplicationDocumentsDirectory();
      final cleansedFileName = '${widget.userName}_cleansed.csv';
      final cleansedFilePath = path.join(directory.path, cleansedFileName);
      final cleansedFile = File(cleansedFilePath);
      await cleansedFile.writeAsString(cleansedCsv.toString());

      if (mounted) {
        setState(() {
          _cleansedCsvPath = cleansedFilePath;
          _poseInfo = 'Cleansed CSV generated successfully!';
        });
      }

      // Save cleansed path to SharedPreferences
      saved['CleansedCsvPath'] = cleansedFilePath;
      await prefs.setString(key, jsonEncode(saved));
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Data cleansing completed: $cleansedFileName')),
      );

    } catch (e) {
      if (mounted) {
        setState(() {
          _poseInfo = 'Error running data cleansing: $e';
        });
      }
      print('Error details: $e');
    }
  }

  double _calculateStandardDeviation(List<double> values) {
    if (values.isEmpty) return 0.0;
    
    final mean = values.reduce((a, b) => a + b) / values.length;
    final squaredDifferences = values.map((value) => math.pow(value - mean, 2));
    final variance = squaredDifferences.reduce((a, b) => a + b) / values.length;
    return math.sqrt(variance);
  }


  double _calculateAngle(List<double> a, List<double> b, List<double> c) {
   
    final double radians = math.atan2(c[1] - b[1], c[0] - b[0]) - 
                          math.atan2(a[1] - b[1], a[0] - b[0]);
    
    double angle = (radians * 180.0 / math.pi).abs();
    
    if (angle > 180.0) {
      angle = 360.0 - angle;
    }
    
    return angle;
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      _stopTimer(); 
      
      if (mounted) {
        setState(() {
          _isRecording = false;
          _poseInfo = 'Recording stopped. Saving data...';
        });
      }

      try {
        final directory = await getApplicationDocumentsDirectory();
        final fileName = '${widget.userName}_poses_${DateTime.now().millisecondsSinceEpoch}.csv';
        final filePath = path.join(directory.path, fileName);
        final file = File(filePath);

        await file.writeAsString(_csvData.toString());

        print('Pose data saved to: $filePath');

        _lastSavedFilePath = filePath;

        final prefs = await SharedPreferences.getInstance();
        final key = '${widget.userName}:data';
        final data = prefs.getString(key);
        final saved = data != null ? jsonDecode(data) : {};
        saved['PoseDataPath'] = filePath;
        await prefs.setString(key, jsonEncode(saved));

        await _processPoseData(filePath);
        await _calculateArmSeparation(_lastSavedFilePath!);
        await _calculateHandSeparation(_lastSavedFilePath!);
        await _calculateTrunkSwing(_lastSavedFilePath!);
        await _calculateHeelSeparation(_lastSavedFilePath!);

        // Run data cleansing after all CSVs are generated
        await _runDataCleansingScript();

        if (mounted) {
          setState(() {
            _hasRecorded = true;
            _poseInfo = 'Recording saved! Duration: ${_formatDuration(_recordingDuration)}';
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pose data saved successfully: $fileName (${_formatDuration(_recordingDuration)})')),
        );

      } catch (e) {
        print('Error saving file: $e');
        if (mounted) {
          setState(() {
            _poseInfo = 'Error saving file: $e';
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving file: $e')),
        );
      }

    } else if (_hasRecorded) {
      await _deleteOldFile();
      
      _csvData.clear();
      _csvData.writeln('timestamp,landmark_type,x,y,z,likelihood');
      if (mounted) {
        setState(() {
          _isRecording = true;
          _hasRecorded = false;
          _lastSavedFilePath = null;
          _recordingDuration = Duration.zero; 
          _poseInfo = 'Recording...';
        });
      }
      
      _startTimer();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Previous recording deleted. Starting new recording...')),
      );

    } else {
      _csvData.clear();
      _csvData.writeln('timestamp,landmark_type,x,y,z,likelihood');
      if (mounted) {
        setState(() {
          _isRecording = true;
          _poseInfo = 'Recording...';
        });
      }
      
      _startTimer(); 
    }
  }

  Future<void> _shareCSVFile() async {
    try {
      List<XFile> filesToShare = [];
      List<String> fileNames = [];

      final prefs = await SharedPreferences.getInstance();
      final key = '${widget.userName}:data';
      final data = prefs.getString(key);
      final saved = data != null ? jsonDecode(data) : {};

      final demographicsPath = saved['DemographicsPath'] as String?;
      if (demographicsPath != null && File(demographicsPath).existsSync()) {
        filesToShare.add(XFile(demographicsPath));
        fileNames.add(path.basename(demographicsPath));
      }

      final poseDataPath = saved['PoseDataPath'] as String?;
      if (poseDataPath != null && File(poseDataPath).existsSync()) {
        filesToShare.add(XFile(poseDataPath));
        fileNames.add(path.basename(poseDataPath));
      }

      final armSeparationPath = saved['ArmSeparationPath'] as String?;
      if (armSeparationPath != null && File(armSeparationPath).existsSync()) {
        filesToShare.add(XFile(armSeparationPath));
        fileNames.add(path.basename(armSeparationPath));
      }

      final handSeparationPath = saved['HandSeparationPath'] as String?;
      if (handSeparationPath != null && File(handSeparationPath).existsSync()) {
        filesToShare.add(XFile(handSeparationPath));
        fileNames.add(path.basename(handSeparationPath));
      }

      final trunkSwingPath = saved['TrunkSwingPath'] as String?;
      if (trunkSwingPath != null && File(trunkSwingPath).existsSync()) {
        filesToShare.add(XFile(trunkSwingPath));
        fileNames.add(path.basename(trunkSwingPath));
      }

      final heelSeparationPath = saved['HeelSeparationPath'] as String?;
      if (heelSeparationPath != null && File(heelSeparationPath).existsSync()) {
        filesToShare.add(XFile(heelSeparationPath));
        fileNames.add(path.basename(heelSeparationPath));
      }

      final cleansedCsvPath = saved['CleansedCsvPath'] as String?;
      if (cleansedCsvPath != null && File(cleansedCsvPath).existsSync()) {
        filesToShare.add(XFile(cleansedCsvPath));
        fileNames.add(path.basename(cleansedCsvPath));
      }

      if (filesToShare.isNotEmpty) {
        await Share.shareXFiles(
          filesToShare,
          text: 'Fall Risk Assessment data for ${widget.userName}\n\nFiles included:\n${fileNames.map((name) => '• $name').join('\n')}',
          subject: 'Fall Risk Assessment - Complete Data Package',
        );
        
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sharing ${filesToShare.length} file(s): ${fileNames.join(', ')}')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No files to share. Please complete the assessment first.')),
        );
      }
    } catch (e) {
      print('Error sharing files: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sharing files: $e')),
      );
    }
  }

  Future<void> _deleteOldFile() async {
    if (_lastSavedFilePath != null && File(_lastSavedFilePath!).existsSync()) {
      try {
        await File(_lastSavedFilePath!).delete();
        print('Deleted old CSV file: $_lastSavedFilePath');
      } catch (e) {
        print('Error deleting old file: $e');
      }
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
        actions: [
          IconButton(
            icon: Icon(Icons.share),
            onPressed: _shareCSVFile,
            tooltip: 'Share CSV File',
          ),
        ],
      ),
      body: Center(
        child: !_isCameraInitialized
            ? CircularProgressIndicator()
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(height: 20),
                    
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: _toggleRecording,
                          child: Text(_isRecording 
                              ? 'Stop & Save Pose Data' 
                              : _hasRecorded 
                                  ? 'Retake' 
                                  : 'Start Recording'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isRecording 
                                ? Colors.red 
                                : _hasRecorded 
                                    ? Colors.orange 
                                    : Colors.green,
                          ),
                        ),
                        SizedBox(width: 10),
                        ElevatedButton.icon(
                          onPressed: _shareCSVFile,
                          icon: Icon(Icons.share),
                          label: Text('Share CSV'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    
                    if (_hasRecorded && !_isRecording) ...[
                      SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: widget.onNext,
                        child: Text('Continue to Next Step'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                    
                    SizedBox(height: 10),
                    Text(_poseInfo ?? 'Point the camera at a person'),
                    SizedBox(height: 10),
                    AspectRatio(
                      aspectRatio: 9 / 16,
                      child: Stack(
                        children: [
                          CameraPreview(_controller!),
                          
                          if (_isRecording) 
                            Positioned(
                              top: 16,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.7),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        _formatDuration(_recordingDuration),
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          
                          if (_controller!.value.previewSize != null)
                            CustomPaint(
                              painter: PosePainter(
                                _poses,
                                _controller!.value.previewSize!,
                                _rotation,
                              ),
                              size: Size.infinite,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

double translateX(
    double x, InputImageRotation rotation, Size size, Size absoluteImageSize) {
  switch (rotation) {
    case InputImageRotation.rotation90deg:
      return x *
          size.width /
          (Platform.isIOS ? absoluteImageSize.width : absoluteImageSize.height);
    case InputImageRotation.rotation270deg:
      return size.width -
          x *
              size.width /
              (Platform.isIOS
                  ? absoluteImageSize.width
                  : absoluteImageSize.height);
    default:
      return x * size.width / absoluteImageSize.width;
  }
}

double translateY(
    double y, InputImageRotation rotation, Size size, Size absoluteImageSize) {
  switch (rotation) {
    case InputImageRotation.rotation90deg:
    case InputImageRotation.rotation270deg:
      return y *
          size.height /
          (Platform.isIOS ? absoluteImageSize.height : absoluteImageSize.width);
    default:
      return y * size.height / absoluteImageSize.height;
  }
}

class PosePainter extends CustomPainter {
  PosePainter(this.poses, this.absoluteImageSize, this.rotation);

  final List<Pose> poses;
  final Size absoluteImageSize;
  final InputImageRotation rotation;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..color = Colors.green;

    final leftPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.yellow;

    final rightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.blueAccent;

    for (final pose in poses) {
      pose.landmarks.forEach((_, landmark) {
        canvas.drawCircle(
            Offset(
              translateX(landmark.x, rotation, size, absoluteImageSize),
              translateY(landmark.y, rotation, size, absoluteImageSize),
            ),
            1,
            paint);
      });

      void paintLine(
          PoseLandmarkType type1, PoseLandmarkType type2, Paint paintType) {
        final PoseLandmark joint1 = pose.landmarks[type1]!;
        final PoseLandmark joint2 = pose.landmarks[type2]!;
        canvas.drawLine(
            Offset(translateX(joint1.x, rotation, size, absoluteImageSize),
                translateY(joint1.y, rotation, size, absoluteImageSize)),
            Offset(translateX(joint2.x, rotation, size, absoluteImageSize),
                translateY(joint2.y, rotation, size, absoluteImageSize)),
            paintType);
      }

      paintLine(
          PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow, leftPaint);
      paintLine(
          PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist, leftPaint);
      paintLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow,
          rightPaint);
      paintLine(
          PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist, rightPaint);

      paintLine(
          PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip, leftPaint);
      paintLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip,
          rightPaint);

      paintLine(
          PoseLandmarkType.leftHip, PoseLandmarkType.leftAnkle, leftPaint);
      paintLine(
          PoseLandmarkType.rightHip, PoseLandmarkType.rightAnkle, rightPaint);
    }
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) {
    return oldDelegate.absoluteImageSize != absoluteImageSize ||
        oldDelegate.poses != poses;
  }
}


class SensorPageWrapper extends StatelessWidget {
  final String userName;
  SensorPageWrapper({required this.userName});

  @override
  Widget build(BuildContext context) {
    return SensorPage(
      userName: userName,
      onNext: () {
        // Assessment completed, go back to user selection
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fall risk assessment completed!')),
        );
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => UserSelectionPage()));
      },
    );
  }
}

class SensorPage extends StatefulWidget {
  final String userName;
  final VoidCallback onNext;

  const SensorPage({required this.userName, required this.onNext});

  @override
  _SensorPageState createState() => _SensorPageState();
}

class _SensorPageState extends State<SensorPage> {
  bool _isConnected = false;
  String _connectionStatus = 'Not connected';
  bool _isRecording = false;
  final StringBuffer _sensorCsvData = StringBuffer();
  Timer? _sensorTimer;
  String? _lastSensorFilePath;
  DateTime? _recordingStartTime;

  @override
  void dispose() {
    _sensorTimer?.cancel();
    super.dispose();
  }

  Future<void> _simulateConnection() async {
    setState(() {
      _connectionStatus = 'Connecting to simulated sensor...';
    });

    await Future.delayed(Duration(seconds: 2));

    setState(() {
      _isConnected = true;
      _connectionStatus = 'Connected to Simulated IMU Sensor';
    });

    // Save connection status
    final prefs = await SharedPreferences.getInstance();
    final key = '${widget.userName}:data';
    final data = prefs.getString(key);
    final saved = data != null ? jsonDecode(data) : {};
    saved['SensorConnected'] = true;
    saved['SensorDeviceName'] = 'Simulated IMU Sensor';
    await prefs.setString(key, jsonEncode(saved));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Successfully connected to simulated sensor!')),
    );
  }

  Future<void> _disconnectSensor() async {
    setState(() {
      _isConnected = false;
      _connectionStatus = 'Disconnected';
    });

    final prefs = await SharedPreferences.getInstance();
    final key = '${widget.userName}:data';
    final data = prefs.getString(key);
    final saved = data != null ? jsonDecode(data) : {};
    saved['SensorConnected'] = false;
    saved.remove('SensorDeviceName');
    await prefs.setString(key, jsonEncode(saved));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sensor disconnected')),
    );
  }

  Future<void> _startSensorRecording() async {
    if (!_isConnected) return;
    
    setState(() {
      _isRecording = true;
    });
    
    // Initialize CSV with headers
    _sensorCsvData.clear();
    _sensorCsvData.writeln('timestamp,accel_x,accel_y,accel_z,gyro_x,gyro_y,gyro_z,mag_x,mag_y,mag_z');
    _recordingStartTime = DateTime.now();
    
    // Simulate sensor data collection at 50Hz (20ms intervals)
    _sensorTimer = Timer.periodic(Duration(milliseconds: 20), (timer) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final random = math.Random();
      
      // Generate realistic sensor data with some noise
      final accelX = (math.sin(timestamp / 200.0) * 2.0 + random.nextDouble() * 0.5 - 0.25);
      final accelY = (9.8 + math.cos(timestamp / 300.0) * 1.0 + random.nextDouble() * 0.3 - 0.15);
      final accelZ = (math.sin(timestamp / 250.0) * 1.5 + random.nextDouble() * 0.4 - 0.2);
      final gyroX = (math.cos(timestamp / 400.0) * 0.5 + random.nextDouble() * 0.1 - 0.05);
      final gyroY = (math.sin(timestamp / 350.0) * 0.3 + random.nextDouble() * 0.08 - 0.04);
      final gyroZ = (math.cos(timestamp / 450.0) * 0.2 + random.nextDouble() * 0.06 - 0.03);
      final magX = (25.0 + math.sin(timestamp / 1000.0) * 5.0 + random.nextDouble() * 2.0 - 1.0);
      final magY = (15.0 + math.cos(timestamp / 800.0) * 3.0 + random.nextDouble() * 1.5 - 0.75);
      final magZ = (-40.0 + math.sin(timestamp / 600.0) * 2.0 + random.nextDouble() * 1.0 - 0.5);
      
      final row = [
        timestamp,
        accelX.toStringAsFixed(4),
        accelY.toStringAsFixed(4),
        accelZ.toStringAsFixed(4),
        gyroX.toStringAsFixed(4),
        gyroY.toStringAsFixed(4),
        gyroZ.toStringAsFixed(4),
        magX.toStringAsFixed(4),
        magY.toStringAsFixed(4),
        magZ.toStringAsFixed(4),
      ];
      _sensorCsvData.writeln(row.join(','));
    });
  }

  Future<void> _stopSensorRecording() async {
    if (!_isRecording) return;
    
    setState(() {
      _isRecording = false;
    });
    
    _sensorTimer?.cancel();
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = '${widget.userName}_sensor_${DateTime.now().millisecondsSinceEpoch}.csv';
      final filePath = path.join(directory.path, fileName);
      final file = File(filePath);

      await file.writeAsString(_sensorCsvData.toString());
      _lastSensorFilePath = filePath;

      // Save sensor data path to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final key = '${widget.userName}:data';
      final data = prefs.getString(key);
      final saved = data != null ? jsonDecode(data) : {};
      saved['SensorDataPath'] = filePath;
      await prefs.setString(key, jsonEncode(saved));

      final recordingDuration = DateTime.now().difference(_recordingStartTime!);
      print('Sensor data saved to: $filePath');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sensor data saved: $fileName (${_formatDuration(recordingDuration)})')),
      );
      
    } catch (e) {
      print('Error saving sensor data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving sensor data: $e')),
      );
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  Future<void> _shareCSVFile() async {
    try {
      List<XFile> filesToShare = [];
      List<String> fileNames = [];

      final prefs = await SharedPreferences.getInstance();
      final key = '${widget.userName}:data';
      final data = prefs.getString(key);
      final saved = data != null ? jsonDecode(data) : {};

      // Add sensor data if available
      final sensorDataPath = saved['SensorDataPath'] as String?;
      if (sensorDataPath != null && File(sensorDataPath).existsSync()) {
        filesToShare.add(XFile(sensorDataPath));
        fileNames.add(path.basename(sensorDataPath));
      }

      // Add all other files from previous steps
      final demographicsPath = saved['DemographicsPath'] as String?;
      if (demographicsPath != null && File(demographicsPath).existsSync()) {
        filesToShare.add(XFile(demographicsPath));
        fileNames.add(path.basename(demographicsPath));
      }

      final cleansedCsvPath = saved['CleansedCsvPath'] as String?;
      if (cleansedCsvPath != null && File(cleansedCsvPath).existsSync()) {
        filesToShare.add(XFile(cleansedCsvPath));
        fileNames.add(path.basename(cleansedCsvPath));
      }

      if (filesToShare.isNotEmpty) {
        await Share.shareXFiles(
          filesToShare,
          text: 'Complete Fall Risk Assessment data for ${widget.userName}\n\nFiles included:\n${fileNames.map((name) => '• $name').join('\n')}',
          subject: 'Fall Risk Assessment - Complete Data Package',
        );
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sharing ${filesToShare.length} file(s): ${fileNames.join(', ')}')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No files to share. Please complete the assessment first.')),
        );
      }
    } catch (e) {
      print('Error sharing files: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sharing files: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Sensor Data Collection'),
        leading: BackButton(
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => VideoPageWrapper(userName: widget.userName),
              ),
            );
          },
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.share),
            onPressed: _shareCSVFile,
            tooltip: 'Share All Data',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isConnected ? Icons.sensors : Icons.sensor_occupied,
              size: 80,
              color: _isConnected ? Colors.green : Colors.grey,
            ),
            SizedBox(height: 20),
            
            Text(
              'Sensor Status',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            
            Text(
              _connectionStatus,
              style: TextStyle(
                fontSize: 16,
                color: _isConnected ? Colors.green : Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            
            if (_isRecording) ...[
              SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.fiber_manual_record, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Recording sensor data...',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
            
            SizedBox(height: 30),

            if (!_isConnected) ...[
              ElevatedButton.icon(
                onPressed: _simulateConnection,
                icon: Icon(Icons.sensors),
                label: Text('Connect to Simulated Sensor'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
              SizedBox(height: 20),
              Text(
                'Note: This is a simulated sensor for demonstration purposes.\nIn a real implementation, this would connect to a physical IMU sensor.',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],

            if (_isConnected) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isRecording ? _stopSensorRecording : _startSensorRecording,
                    icon: Icon(_isRecording ? Icons.stop : Icons.play_arrow),
                    label: Text(_isRecording ? 'Stop Recording' : 'Start Recording'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isRecording ? Colors.red : Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _disconnectSensor,
                    icon: Icon(Icons.power_off),
                    label: Text('Disconnect'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: _shareCSVFile,
                icon: Icon(Icons.share),
                label: Text('Share All Assessment Data'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => widget.onNext(),
                child: Text('Complete Assessment'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],

            if (!_isConnected) ...[
              SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _shareCSVFile,
                icon: Icon(Icons.share),
                label: Text('Share Assessment Data'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
              SizedBox(height: 10),
              TextButton(
                onPressed: () => widget.onNext(),
                child: Text('Complete Assessment Without Sensor'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}