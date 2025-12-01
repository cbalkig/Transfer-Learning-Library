import os
import argparse
import yaml

def create_list(root_dir, sub_folder, output_filename):
    """
    Generates a text file list of images and class indices.
    args:
        root_dir: The base directory containing the datasets
        sub_folder: The specific folder (source or target) inside root_dir
        output_filename: The path where the .txt list will be saved
    """
    full_path = os.path.join(root_dir, sub_folder)

    if not os.path.exists(full_path):
        print(f"Error: Directory {full_path} does not exist.")
        return []

    # Filter for directories only and sort them to ensure consistent indexing
    classes = sorted([d for d in os.listdir(full_path) if os.path.isdir(os.path.join(full_path, d))])
    class_to_idx = {cls_name: i for i, cls_name in enumerate(classes)}

    with open(output_filename, 'w') as f:
        for cls_name in classes:
            cls_folder = os.path.join(full_path, cls_name)
            for img_name in os.listdir(cls_folder):
                if img_name.lower().endswith(('.png', '.jpg', '.jpeg', '.bmp')):
                    # Construct relative path from root if needed, or absolute path
                    # Here we keep the structure: path/to/image label_index
                    image_path = os.path.join(full_path, cls_name, img_name)
                    f.write(f"{image_path} {class_to_idx[cls_name]}\n")

    print(f"Generated {output_filename} from {sub_folder} with {len(classes)} classes.")
    return classes

def main():
    parser = argparse.ArgumentParser(description="Generate file lists from YAML config.")
    parser.add_argument("--cfg_file", required=True, type=str, help="Path to the YAML configuration file")
    args = parser.parse_args()

    # Load YAML configuration
    with open(args.cfg, 'r') as f:
        config = yaml.safe_load(f)

    root_dir = config.get('root_dir')
    source_folder = config.get('source')
    target_folder = config.get('target')

    # Define output filenames based on source/target names
    source_output_txt = os.path.join(root_dir, f"{source_folder}_list.txt")
    target_output_txt = os.path.join(root_dir, f"{target_folder}_list.txt")

    print(f"Processing configuration from: {args.cfg}")

    # Generate lists
    source_classes = create_list(root_dir, source_folder, source_output_txt)
    target_classes = create_list(root_dir, target_folder, target_output_txt)

    # Sanity check
    if source_classes and target_classes:
        if source_classes != target_classes:
            print("\nWARNING: Class mismatch between Source and Target!")
            print(f"Source ({source_folder}) classes: {len(source_classes)}")
            print(f"Target ({target_folder}) classes: {len(target_classes)}")

            # Optional: Print differences
            set_source = set(source_classes)
            set_target = set(target_classes)
            diff = set_source.symmetric_difference(set_target)
            if diff:
                print(f"Different classes: {diff}")
        else:
            print("\nSUCCESS: Source and Target classes match perfectly.")

if __name__ == "__main__":
    main()