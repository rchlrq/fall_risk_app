import 'package:flutter/material.dart';
import 'package:pytorch_lite/pytorch_lite.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // Correct class name is ModelObjectDetection, not TorchModule
    final model = await PytorchLite.loadObjectDetectionModel(
      'assets/model_mobile.pt',
      80, // number of classes
      640, 640, // input dimensions
      labelPath: 'assets/labels.txt', // optional
    );
    print('Model loaded successfully');
  } catch (e) {
    print('Error loading model: $e');
  }
}