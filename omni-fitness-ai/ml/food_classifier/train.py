"""
Free open-source food tracker model training
Dataset: Kaggle Food-101 (https://www.kaggle.com/datasets/dansbecker/food-101) or Food2K
Model: MobileNetV2 -> TFLite (runs on-device via expo-tflite / tflite-react-native)

FREE training: runs on Kaggle Notebooks (free GPU) or Colab.

Steps:
1. kaggle datasets download -d dansbecker/food-101 -p data/
2. pip install -r requirements.txt
3. python ml/food_classifier/train.py --data data/food-101 --epochs 10 --export tflite

Output: ml/food_classifier/export/food_model.tflite + labels.txt
Drop into app bundle: assets/ml/food_model.tflite
App loads via src/lib/food-recognition.ts (local TFLite path)
"""

import argparse
import os
import pathlib

def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument('--data', type=str, required=False, default='data/food-101',
                   help='Path to food-101 extracted folder (contains images/ and meta/)')
    p.add_argument('--epochs', type=int, default=8)
    p.add_argument('--batch', type=int, default=32)
    p.add_argument('--img', type=int, default=224)
    p.add_argument('--export', type=str, default='tflite', choices=['tflite', 'onnx', 'saved_model'])
    return p.parse_args()

def main():
    args = parse_args()
    print(f"[train] data={args.data} epochs={args.epochs} export={args.export}")

    # Lazy imports so script can be inspected without TF installed
    try:
        import tensorflow as tf
        from tensorflow.keras.applications import MobileNetV2
        from tensorflow.keras import layers, Model
    except ImportError:
        print("[train] TensorFlow not installed. Install with: pip install tensorflow")
        print("[train] For quick demo without training, use heuristic mode in src/lib/food-recognition.ts (no model needed).")
        print("[train] To train free on Kaggle: open Kaggle Notebook, add Food-101 dataset, pip install tensorflow, run this script.")
        return

    data_dir = pathlib.Path(args.data)
    if not data_dir.exists():
        print(f"[train] Data dir not found: {data_dir}")
        print("[train] Download: kaggle datasets download -d dansbecker/food-101 -p data/ && unzip data/food-101.zip -d data/")
        return

    # Load dataset
    train_ds = tf.keras.utils.image_dataset_from_directory(
        data_dir / "images",
        validation_split=0.2,
        subset="training",
        seed=123,
        image_size=(args.img, args.img),
        batch_size=args.batch,
    )
    val_ds = tf.keras.utils.image_dataset_from_directory(
        data_dir / "images",
        validation_split=0.2,
        subset="validation",
        seed=123,
        image_size=(args.img, args.img),
        batch_size=args.batch,
    )
    class_names = train_ds.class_names
    os.makedirs("ml/food_classifier/export", exist_ok=True)
    with open("ml/food_classifier/export/labels.txt", "w") as f:
        f.write("\n".join(class_names))
    print(f"[train] Classes: {len(class_names)} e.g. {class_names[:5]}")

    AUTOTUNE = tf.data.AUTOTUNE
    train_ds = train_ds.cache().shuffle(1000).prefetch(AUTOTUNE)
    val_ds = val_ds.cache().prefetch(AUTOTUNE)

    # Transfer learning
    base = MobileNetV2(input_shape=(args.img, args.img, 3), include_top=False, weights='imagenet')
    base.trainable = False
    inputs = tf.keras.Input(shape=(args.img, args.img, 3))
    x = tf.keras.applications.mobilenet_v2.preprocess_input(inputs)
    x = base(x, training=False)
    x = layers.GlobalAveragePooling2D()(x)
    x = layers.Dropout(0.2)(x)
    outputs = layers.Dense(len(class_names), activation='softmax')(x)
    model = Model(inputs, outputs)
    model.compile(optimizer='adam', loss='sparse_categorical_crossentropy', metrics=['accuracy'])
    model.summary()

    model.fit(train_ds, validation_data=val_ds, epochs=args.epochs)

    # Fine-tune last layers
    base.trainable = True
    for layer in base.layers[:-30]:
        layer.trainable = False
    model.compile(optimizer=tf.keras.optimizers.Adam(1e-5), loss='sparse_categorical_crossentropy', metrics=['accuracy'])
    model.fit(train_ds, validation_data=val_ds, epochs=2)

    # Export
    if args.export == 'tflite':
        converter = tf.lite.TFLiteConverter.from_keras_model(model)
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        tflite_model = converter.convert()
        with open("ml/food_classifier/export/food_model.tflite", "wb") as f:
            f.write(tflite_model)
        print("[train] Exported ml/food_classifier/export/food_model.tflite")
        print("[train] Copy to: assets/ml/food_model.tflite and add to app.json assets")
    elif args.export == 'saved_model':
        model.save("ml/food_classifier/export/saved_model")
        print("[train] SavedModel exported")

if __name__ == "__main__":
    main()
