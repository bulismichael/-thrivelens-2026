import os
from torch.utils.data import Dataset, DataLoader, random_split
from PIL import Image
from torchvision import transforms


class FoodDataset(Dataset):
    def __init__(self, root_dir, split="train", transform=None):
        self.root_dir = root_dir
        self.split = split
        self.transform = transform
        self.samples = []
        self.class_to_idx = {}

        split_dir = os.path.join(root_dir, split)
        if not os.path.exists(split_dir):
            split_dir = root_dir

        classes = sorted([
            d for d in os.listdir(split_dir)
            if os.path.isdir(os.path.join(split_dir, d))
        ])

        for idx, class_name in enumerate(classes):
            self.class_to_idx[class_name] = idx
            class_dir = os.path.join(split_dir, class_name)
            for img_name in os.listdir(class_dir):
                if img_name.lower().endswith(('.png', '.jpg', '.jpeg')):
                    self.samples.append((
                        os.path.join(class_dir, img_name),
                        idx
                    ))

        self.idx_to_class = {v: k for k, v in self.class_to_idx.items()}

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, idx):
        img_path, label = self.samples[idx]
        image = Image.open(img_path).convert("RGB")

        if self.transform:
            image = self.transform(image)

        return image, label


def get_transforms(config, split="train"):
    mean = config["augmentation"]["normalize_mean"]
    std = config["augmentation"]["normalize_std"]

    if split == "train":
        return transforms.Compose([
            transforms.Resize((256, 256)),
            transforms.RandomCrop(config["data"]["input_size"]),
            transforms.RandomHorizontalFlip(config["augmentation"]["random_flip"]),
            transforms.ColorJitter(config["augmentation"]["color_jitter"]),
            transforms.ToTensor(),
            transforms.Normalize(mean, std),
        ])
    else:
        return transforms.Compose([
            transforms.Resize(tuple(config["model"]["input_size"])),
            transforms.ToTensor(),
            transforms.Normalize(mean, std),
        ])


def get_dataloaders(data_dir, config):
    train_transform = get_transforms(config, "train")
    val_transform = get_transforms(config, "val")

    train_dataset = FoodDataset(data_dir, split="train", transform=train_transform)
    val_dataset = FoodDataset(data_dir, split="val", transform=val_transform)
    test_dataset = FoodDataset(data_dir, split="test", transform=val_transform)

    train_loader = DataLoader(
        train_dataset,
        batch_size=config["training"]["batch_size"],
        shuffle=True,
        num_workers=config["data"]["num_workers"],
        pin_memory=True,
    )
    val_loader = DataLoader(
        val_dataset,
        batch_size=config["training"]["batch_size"],
        shuffle=False,
        num_workers=config["data"]["num_workers"],
        pin_memory=True,
    )
    test_loader = DataLoader(
        test_dataset,
        batch_size=config["training"]["batch_size"],
        shuffle=False,
        num_workers=config["data"]["num_workers"],
        pin_memory=True,
    )

    return train_loader, val_loader, test_loader, train_dataset.class_to_idx
