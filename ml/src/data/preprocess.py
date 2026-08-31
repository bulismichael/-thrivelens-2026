from PIL import Image
from torchvision import transforms


def preprocess_image(image_path, input_size=(224, 224)):
    mean = [0.485, 0.456, 0.406]
    std = [0.229, 0.224, 0.225]

    transform = transforms.Compose([
        transforms.Resize(input_size),
        transforms.ToTensor(),
        transforms.Normalize(mean, std),
    ])

    image = Image.open(image_path).convert("RGB")
    return transform(image).unsqueeze(0)


def denormalize(tensor):
    mean = [0.485, 0.456, 0.406]
    std = [0.229, 0.224, 0.225]

    for t, m, s in zip(tensor, mean, std):
        t.mul_(s).add_(m)

    return tensor.clamp(0, 1)
