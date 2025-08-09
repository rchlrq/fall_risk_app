# Python script to convert PyTorch to TFLite
import torch
import tensorflow as tf
from torch.utils.mobile_optimizer import optimize_for_mobile

# Load your PyTorch model
model = torch.load('C:\\rachel\\aaase\\model_mobile.pt')
model.eval()

# Convert to TorchScript
traced_model = torch.jit.trace(model, torch.randn(1, 3, 224, 224))

# Then use ai-edge-torch or manual conversion to TFLite
# Or use ONNX as intermediate format:
# PyTorch -> ONNX -> TensorFlow -> TensorFlow Lite