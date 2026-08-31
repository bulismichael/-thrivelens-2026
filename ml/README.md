# Food Training Pipeline

ML pipeline for food recognition and nutrition estimation.

## Structure

```
ml/
├── configs/              # Training hyperparameters
├── data/
│   ├── raw/              # Original dataset (Food-101)
│   ├── processed/        # Preprocessed data
│   └── augmented/        # Augmented data
├── models/
│   ├── checkpoints/      # Saved model checkpoints
│   └── exported/         # ONNX exported models
├── src/
│   ├── data/             # Dataset loading, preprocessing
│   ├── models/           # Model architectures
│   ├── training/         # Training loop, checkpointing
│   ├── evaluation/       # Metrics, confusion matrix
│   └── inference/        # Prediction API
├── tests/                # Unit tests
├── train.py              # Main training script
└── requirements.txt      # Python dependencies
```

## Setup

```bash
cd ml
pip install -r requirements.txt
```

## Dataset

Place [Food-101](https://www.kaggle.com/dansbecker/food-101) dataset in `data/raw/`:

```
data/raw/
├── apple_pie/
│   ├── 1011328.jpg
│   └── ...
├── baby_back_ribs/
└── ... (101 classes)
```

## Training

```bash
python train.py
```

## Export to ONNX

```bash
python -m src.export
```

## Inference

```python
from src.inference import FoodPredictor

predictor = FoodPredictor(
    model_path="models/checkpoints/best_model.pt",
    class_names=["apple_pie", "pizza", "sushi", ...]
)
results = predictor.predict("path/to/food.jpg")
print(results)  # [{"class": "pizza", "confidence": 0.95}, ...]
```
