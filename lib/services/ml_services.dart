import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:fall_risk/models/prediction_result.dart';

class MLService {
  static const String MODEL_PATH = 'assets/model.tflite';
  static const String METADATA_PATH = 'assets/model_metadata.json';

  Interpreter? _interpreter;
  Map<String, dynamic>? _metadata;
  bool _isInitialized = false;

  // Singleton pattern
  static final MLService _instance = MLService._internal();
  factory MLService() => _instance;
  MLService._internal();

  /// Initialize the ML model
  Future<void> initialize() async {
  if (_isInitialized) {
    print('ML Service already initialized');
    return;
  }

  print('Loading model from asset: $MODEL_PATH');
  try {
    // Load model file to verify existence
    await rootBundle.load(MODEL_PATH);

    // Interpreter.fromAsset uses relative path inside assets declared in pubspec.yaml
    // So pass relative path WITHOUT 'assets/' prefix
    _interpreter = await Interpreter.fromAsset('assets/model.tflite');


    print('✅ Model loaded successfully');

    // Load metadata if present
    try {
      String metadataJson = await rootBundle.loadString(METADATA_PATH);
      _metadata = json.decode(metadataJson);
      print('✅ Metadata loaded successfully');
      print('📊 Model info: Threshold=${_metadata!['threshold']}, Accuracy=${_metadata!['accuracy']}');
    } catch (e) {
      print('⚠️ Metadata not found or failed to load, using defaults');
      _metadata = {
        'threshold': 0.5,
        'selected_features': List.generate(19, (i) => i),
        'accuracy': 0.0
      };
    }

    // Validate input/output tensor shapes and types
    final inputTensors = _interpreter!.getInputTensors();
    final outputTensors = _interpreter!.getOutputTensors();

    if (inputTensors.isEmpty) throw Exception('Model has no input tensors');
    if (outputTensors.isEmpty) throw Exception('Model has no output tensors');

    final inputShape = inputTensors.first.shape;
    final outputShape = outputTensors.first.shape;

    print('📋 Model Input Shape: $inputShape');
    print('📋 Model Output Shape: $outputShape');

    if (inputShape.length != 2 || inputShape[1] != 19) {
      print('⚠️ Warning: Expected input shape [batch_size, 19], got $inputShape');
    }

    if (outputShape.length != 2 || outputShape[1] != 1) {
      print('⚠️ Warning: Expected output shape [batch_size, 1], got $outputShape');
    }

    _isInitialized = true;
    print('🎉 ML Service initialized successfully!');
  } catch (e) {
    print('❌ Failed to initialize ML Service: $e');
    _cleanup();
    rethrow;
  }
}
  /// Make prediction with your 19 features
  Future<PredictionResult> predict(List<double> features) async {
    if (!_isInitialized) {
      throw Exception('ML Service not initialized. Call initialize() first.');
    }

    if (features.length != 19) {
      throw Exception('Expected 19 features, got ${features.length}');
    }

    try {
      // Prepare input tensor shaped [1, 19] as List<List<double>>
      final input = [features];

      // Prepare output buffer shaped [1, 1]
      final output = List.generate(1, (_) => List.filled(1, 0.0));

      // Run inference
      _interpreter!.run(input, output);

      double probability = output[0][0];
      probability = probability.clamp(0.0, 1.0);

      double threshold = (_metadata?['threshold'] as num?)?.toDouble() ?? 0.5;
      bool prediction = probability >= threshold;
      double confidence = prediction ? probability : (1.0 - probability);

      return PredictionResult(
        prediction: prediction,
        probability: probability,
        confidence: confidence,
        threshold: threshold,
      );
    } catch (e) {
      print('❌ Prediction failed: $e');
      throw Exception('Prediction failed: $e');
    }
  }

  Map<String, dynamic>? get metadata => _metadata;
  bool get isInitialized => _isInitialized;

  void _cleanup() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }

  void dispose() {
    _cleanup();
    print('🧹 ML Service disposed');
  }
}
