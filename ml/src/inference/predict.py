import torch
from PIL import Image
from ..models.classifier import FoodClassifier
from ..data.preprocess import preprocess_image


class FoodPredictor:
    def __init__(self, model_path, class_names, device="cpu"):
        self.device = torch.device(device)
        self.class_names = class_names

        checkpoint = torch.load(model_path, map_location=self.device)
        self.model = FoodClassifier(num_classes=len(class_names))
        self.model.load_state_dict(checkpoint["model_state_dict"])
        self.model.to(self.device)
        self.model.eval()

    def predict(self, image_path, top_k=3):
        input_tensor = preprocess_image(image_path).to(self.device)

        with torch.no_grad():
            outputs = self.model(input_tensor)
            probabilities = torch.nn.functional.softmax(outputs, dim=1)
            top_probs, top_indices = probabilities.topk(top_k, dim=1)

        results = []
        for prob, idx in zip(top_probs[0], top_indices[0]):
            results.append({
                "class": self.class_names[idx.item()],
                "confidence": prob.item(),
            })

        return results

    def predict_onnx(self, image_path, onnx_path, top_k=3):
        import onnxruntime as ort

        session = ort.InferenceSession(onnx_path)
        input_tensor = preprocess_image(image_path).numpy()

        outputs = session.run(None, {"input": input_tensor})
        probabilities = torch.nn.functional.softmax(
            torch.tensor(outputs[0]), dim=1
        )
        top_probs, top_indices = probabilities.topk(top_k, dim=1)

        results = []
        for prob, idx in zip(top_probs[0], top_indices[0]):
            results.append({
                "class": self.class_names[idx.item()],
                "confidence": prob.item(),
            })

        return results
