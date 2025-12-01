import os

def create_list(folder_name, output_filename):
    classes = sorted([d for d in os.listdir(folder_name) if os.path.isdir(os.path.join(folder_name, d))])
    class_to_idx = {cls_name: i for i, cls_name in enumerate(classes)}

    with open(output_filename, 'w') as f:
        for cls_name in classes:
            cls_folder = os.path.join(folder_name, cls_name)
            for img_name in os.listdir(cls_folder):
                if img_name.lower().endswith(('.png', '.jpg', '.jpeg', '.bmp')):
                    # Write: relative_path label_index
                    path = os.path.join(folder_name, cls_name, img_name)
                    f.write(f"{path} {class_to_idx[cls_name]}\n")

    print(f"Generated {output_filename} with {len(classes)} classes.")
    return classes

# Generate lists
train_classes = create_list('/Users/c.balkigemirter/PycharmProjects/PhD-UDA-files/Data/BenchmarkData/NeuroDomain-k-fold-1/neuro_domain', '/Users/c.balkigemirter/PycharmProjects/PhD-UDA-files/Data/BenchmarkData/NeuroDomain-k-fold-1/neuro_train.txt')
test_classes = create_list('/Users/c.balkigemirter/PycharmProjects/PhD-UDA-files/Data/BenchmarkData/NeuroDomain-k-fold-1/vegfru-test', '/Users/c.balkigemirter/PycharmProjects/PhD-UDA-files/Data/BenchmarkData/NeuroDomain-k-fold-1/vegfru_test.txt')

# Sanity check
if train_classes != test_classes:
    print("WARNING: Class mismatch between NeuroDomain and VegFru!")
    print(f"Neuro classes: {train_classes}")
    print(f"VegFru classes: {test_classes}")