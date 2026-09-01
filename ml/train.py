import yaml
import torch
from src.models.classifier import create_model
from src.data.dataset import get_dataloaders
from src.training.train import train_model


def main():
    with open("configs/food_classifier.yaml") as f:
        config = yaml.safe_load(f)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Using device: {device}")

    model = create_model(config).to(device)
    print(f"Model: {config['model']['backbone']} | Classes: {config['model']['num_classes']}")

    train_loader, val_loader, test_loader, class_names = get_dataloaders(
        "data/raw", config
    )
    print(f"Train: {len(train_loader.dataset)} | Val: {len(val_loader.dataset)} | Test: {len(test_loader.dataset)}")

    model = train_model(model, train_loader, val_loader, config, device)
    print("Training complete!")


if __name__ == "__main__":
    main()
