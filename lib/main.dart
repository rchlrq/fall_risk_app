import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';

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
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 250,
            child: Text(
              questions[index],
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.left,
            ),
          ),
          SizedBox(width: 30),
          Container(
            width: 120,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Radio<bool>(
                      value: true,
                      groupValue: answers[index],
                      onChanged: (val) {
                        setState(() {
                          answers[index] = val;
                        });
                      },
                    ),
                    Text('Yes'),
                  ],
                ),
                SizedBox(width: 10),
                Row(
                  children: [
                    Radio<bool>(
                      value: false,
                      groupValue: answers[index],
                      onChanged: (val) {
                        setState(() {
                          answers[index] = val;
                        });
                      },
                    ),
                    Text('No'),
                  ],
                ),
              ],
            ),
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
      body: ListView(
        children: [
          ...List.generate(questions.length, _buildQuestionRow),
          SizedBox(height: 20),
          Center(
            child: ElevatedButton(
              onPressed: allAnswered ? _saveAndContinue : null,
              child: Text("Next"),
            ),
          ),
        ],
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
  File? _video;

  Future<bool> _requestPermission(ImageSource source) async {
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      return status.isGranted;
    } else if (source == ImageSource.gallery) {
      final status = await Permission.storage.request();
      return status.isGranted;
    }
    return false;
  }

  Future<void> _pickVideo(ImageSource source) async {
    final hasPermission = await _requestPermission(source);
    if (!hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Permission denied for ${source == ImageSource.camera ? 'camera' : 'gallery'}')),
      );
      return;
    }

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickVideo(source: source);
      if (pickedFile != null) {
        setState(() {
          _video = File(pickedFile.path);
        });

        // Prepare output path for processed video
        final dir = _video!.parent;
        final filename = path.basename(_video!.path);
        final outputPath = path.join(dir.path, 'processed_$filename');

        // Run FFmpeg command to resize video
        final command = '-i "${_video!.path}" -vf scale=640:480 "$outputPath"';

        final session = await FFmpegKit.execute(command);
        final returnCode = await session.getReturnCode();
        if (ReturnCode.isSuccess(returnCode)) {
          print('Video processed successfully: $outputPath');

          final prefs = await SharedPreferences.getInstance();
          final key = '${widget.userName}:data';
          final data = prefs.getString(key);
          final saved = data != null ? jsonDecode(data) : {};
          saved['Processed_Video_path'] = outputPath;
          await prefs.setString(key, jsonEncode(saved));

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Video processed successfully')),
          );
        } else {
          print('Video processing failed with code $returnCode');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Video processing failed')),
          );
        }

        // Save original video path as before
        final prefs = await SharedPreferences.getInstance();
        final key = '${widget.userName}:data';
        final data = prefs.getString(key);
        final saved = data != null ? jsonDecode(data) : {};
        saved['Video_path'] = pickedFile.path;
        await prefs.setString(key, jsonEncode(saved));
      }
    } catch (e) {
      print('Error picking or processing video: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking or processing video')),
      );
    }
  }

  Future<void> _processVideoFrames() async {
    if (_video == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please select a video first')));
      return;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final framesDir = Directory(path.join(tempDir.path, 'extracted_frames'));

      if (await framesDir.exists()) {
        await framesDir.delete(recursive: true);
      }
      await framesDir.create();

      final command =
          '-i "${_video!.path}" -vf fps=1 "${framesDir.path}/frame_%04d.jpg"';

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to extract frames')));
        return;
      }

      final frameFiles = framesDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.jpg'))
          .toList();

      final poseDetector = PoseDetector(
        options: PoseDetectorOptions(mode: PoseDetectionMode.single),
      );

      int frameCount = 0;
      for (final file in frameFiles) {
        final inputImage = InputImage.fromFile(file);
        final poses = await poseDetector.processImage(inputImage);

        for (final pose in poses) {
          for (final landmark in pose.landmarks.values) {
            print(
                'Frame $frameCount, landmark ${landmark.type}: (${landmark.x}, ${landmark.y}, ${landmark.z})');
          }
        }
        frameCount++;
      }
      await poseDetector.close();

      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Processed $frameCount frames for pose detection')));
    } catch (e) {
      print('Error processing video frames: $e');
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error processing video frames')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Video Upload'),
        leading: BackButton(
          onPressed: () {
            Navigator.pushReplacement(
                context, MaterialPageRoute(builder: (_) => FallRiskPage(userName: widget.userName)));
          },
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_video != null) ...[
              Text('Selected video: ${path.basename(_video!.path)}'),
              SizedBox(height: 20),
            ],
            ElevatedButton(
              onPressed: () => _pickVideo(ImageSource.camera),
              child: Text('Record Video'),
            ),
            ElevatedButton(
              onPressed: () => _pickVideo(ImageSource.gallery),
              child: Text('Select Video from Gallery'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _processVideoFrames,
              child: Text('Process Video Frames (Pose Detection)'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: widget.onNext,
              child: Text('Next'),
            ),
          ],
        ),
      ),
    );
  }
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
