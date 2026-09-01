import torch
from src.models.classifier import create_model


def export_to_onnx(model_config, checkpoint_path, output_path="ml/models/exported/food_classifier.onnx"):
    import os
    import glob
    # Resolve checkpoint: if exact path missing, pick best_model_acc*.pt with highest acc
    if not os.path.exists(checkpoint_path):
        candidates = glob.glob(os.path.join(os.path.dirname(checkpoint_path), "best_model_acc*.pt"))
        if candidates:
            checkpoint_path = max(candidates)  # lexicographically highest acc
            print(f"Checkpoint {checkpoint_path} resolved from pattern")
        else:
            raise FileNotFoundError(f"Checkpoint not found: {checkpoint_path} and no best_model_acc*.pt found")
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    model = create_model(model_config)
    checkpoint = torch.load(checkpoint_path, map_location="cpu")
    model.load_state_dict(checkpoint["model_state_dict"])
    model.eval()

    dummy_input = torch.randn(1, 3, 224, 224)

    torch.onnx.export(
        model,
        dummy_input,
        output_path,
        input_names=["input"],
        output_names=["output"],
        dynamic_axes={"input": {0: "batch_size"}, "output": {0: "batch_size"}},
    )
    print(f"ONNX model exported: {output_path}")


if __name__ == "__main__":
    import yaml
    with open("configs/food_classifier.yaml") as f:
        config = yaml.safe_load(f)

    export_to_onnx(config, "ml/models/checkpoints/best_model.pt")
