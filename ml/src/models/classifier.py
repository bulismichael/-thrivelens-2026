import torch
import torch.nn as nn
from torchvision import models


class FoodClassifier(nn.Module):
    def __init__(self, num_classes, backbone="mobilenet_v3_small", dropout=0.2):
        super().__init__()

        if backbone == "mobilenet_v3_small":
            self.backbone = models.mobilenet_v3_small(weights=models.MobileNet_V3_Small_Weights.DEFAULT)
            in_features = self.backbone.classifier[3].in_features
            self.backbone.classifier = nn.Sequential(
                nn.Linear(self.backbone.classifier[0].in_features, 256),
                nn.Hardswish(),
                nn.Dropout(dropout),
                nn.Linear(256, num_classes),
            )
        elif backbone == "mobilenet_v3_large":
            self.backbone = models.mobilenet_v3_large(weights=models.MobileNet_V3_Large_Weights.DEFAULT)
            in_features = self.backbone.classifier[3].in_features
            self.backbone.classifier = nn.Sequential(
                nn.Linear(self.backbone.classifier[0].in_features, 512),
                nn.Hardswish(),
                nn.Dropout(dropout),
                nn.Linear(512, num_classes),
            )
        elif backbone == "efficientnet_b0":
            self.backbone = models.efficientnet_b0(weights=models.EfficientNet_B0_Weights.DEFAULT)
            in_features = self.backbone.classifier[1].in_features
            self.backbone.classifier = nn.Sequential(
                nn.Dropout(dropout),
                nn.Linear(in_features, num_classes),
            )
        else:
            raise ValueError(f"Unsupported backbone: {backbone}")

    def forward(self, x):
        return self.backbone(x)


def create_model(config):
    model = FoodClassifier(
        num_classes=config["model"]["num_classes"],
        backbone=config["model"]["backbone"],
        dropout=config["model"]["dropout"],
    )
    return model
