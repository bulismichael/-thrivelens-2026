# Food Tracker Model — Free Training Pipeline

Train your own food recognition model **for free** using Kaggle's free GPU.

## Quick Start (no cost)

1. Create Kaggle account → https://www.kaggle.com → get API key → `kaggle.json`
2. Open a **Kaggle Notebook** (free 30h GPU/week) and run:

```bash
kaggle datasets download -d dansbecker/food-101 -p data
unzip -q data/food-101.zip -d data
pip install -r ml/food_classifier/requirements.txt
python ml/food_classifier/train.py --data data/food-101 --epochs 8 --export tflite
```

3. Download `ml/food_classifier/export/food_model.tflite` + `labels.txt`
4. Place in Expo app:
```
assets/ml/food_model.tflite
assets/ml/labels.txt
```
Add to `app.json`:
```json
"assetBundlePatterns": ["assets/ml/*"]
```

5. App `src/lib/food-recognition.ts` will auto-detect bundled TFLite and use it. Until then it uses heuristic + optional HuggingFace free inference.

## Alternative: No Training (works today)

App already works **offline without any model**:
- `FOOD_DB` heuristic estimates macros from label
- User types "chicken breast" or picks from suggestions
- Photo is stored, heuristic infers if possible

For better accuracy without training, set `EXPO_PUBLIC_HF_TOKEN` (free at huggingface.co) — app calls `nateraw/food` model free tier.

## Why this is free & open source
- Dataset: Food-101 (CC, Kaggle free)
- Training: Kaggle Notebooks free GPU
- Inference: TFLite on-device (no server cost) or HF free API
- DB: SQLite + Drizzle (OSS), no paid DB
