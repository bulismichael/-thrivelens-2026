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
    # Save versioned file + canonical best_model.pt for export/inference
    filepath = os.path.join(path, f"best_model_acc{accuracy:.2f}.pt")
    canonical = os.path.join(path, "best_model.pt")
    torch.save(checkpoint, filepath)
    torch.save(checkpoint, canonical)
    print(f"Checkpoint saved: {filepath} (+ {canonical})")


def load_checkpoint(filepath, model, optimizer=None):
    checkpoint = torch.load(filepath, map_location="cpu")
    model.load_state_dict(checkpoint["model_state_dict"])
    if optimizer:
        optimizer.load_state_dict(checkpoint["optimizer_state_dict"])
    return model, checkpoint.get("epoch", 0), checkpoint.get("accuracy", 0.0)
