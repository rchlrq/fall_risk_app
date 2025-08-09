class PredictionResult {
  final bool prediction;
  final double probability;
  final double confidence;
  final double threshold;
  final DateTime timestamp;
  
  PredictionResult({
    required this.prediction,
    required this.probability,
    required this.confidence,
    required this.threshold,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
  
  /// Get prediction as readable string
  String get predictionText => prediction ? 'Positive' : 'Negative';
  
  /// Get confidence as percentage
  String get confidencePercentage => '${(confidence * 100).toStringAsFixed(1)}%';
  
  /// Get probability as percentage
  String get probabilityPercentage => '${(probability * 100).toStringAsFixed(1)}%';
  
  /// Convert to JSON
  Map<String, dynamic> toJson() => {
    'prediction': prediction,
    'probability': probability,
    'confidence': confidence,
    'threshold': threshold,
    'timestamp': timestamp.toIso8601String(),
  };
  
  /// Create from JSON
  factory PredictionResult.fromJson(Map<String, dynamic> json) => PredictionResult(
    prediction: json['prediction'],
    probability: json['probability'],
    confidence: json['confidence'],
    threshold: json['threshold'],
    timestamp: DateTime.parse(json['timestamp']),
  );
  
  @override
  String toString() {
    return 'PredictionResult(prediction: $predictionText, '
           'probability: $probabilityPercentage, '
           'confidence: $confidencePercentage)';
  }
}