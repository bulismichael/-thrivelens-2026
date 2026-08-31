import torch
import os


def save_checkpoint(model, optimizer, epoch, accuracy, config, path="ml/models/checkpoints"):
    os.makedirs(path, exist_ok=True)
    checkpoint = {
        "epoch": epoch,
        "model_state_dict": model.state_dict(),
        "optimizer_state_dict": optimizer.state_dict(),
        "accuracy": accuracy,
    }
    filepath = os.path.join(path, f"best_model_acc{accuracy:.2f}.pt")
    torch.save(checkpoint, filepath)
    print(f"Checkpoint saved: {filepath}")


def load_checkpoint(filepath, model, optimizer=None):
    checkpoint = torch.load(filepath, map_location="cpu")
    model.load_state_dict(checkpoint["model_state_dict"])
    if optimizer:
        optimizer.load_state_dict(checkpoint["optimizer_state_dict"])
    return model, checkpoint.get("epoch", 0), checkpoint.get("accuracy", 0.0)
