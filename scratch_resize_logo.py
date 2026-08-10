import os
from PIL import Image

def resize_logo():
    logo_path = r"d:\Users\user\Desktop\atsleadtracker\Assets\Logo\Logo.png"
    if not os.path.exists(logo_path):
        print(f"Error: Logo file not found at {logo_path}")
        return

    original_size = os.path.getsize(logo_path)
    print(f"Original logo file size: {original_size / 1024 / 1024:.2f} MB")

    # Open and resize
    with Image.open(logo_path) as img:
        # Convert to RGBA if not already
        if img.mode != 'RGBA':
            img = img.convert('RGBA')
        
        # Calculate new size maintaining aspect ratio
        max_size = (256, 256)
        img.thumbnail(max_size, Image.Resampling.LANCZOS)
        
        # Save back to same path with optimization
        img.save(logo_path, "PNG", optimize=True)

    new_size = os.path.getsize(logo_path)
    print(f"New compressed logo file size: {new_size / 1024:.2f} KB")
    print("SUCCESS: Logo resized and compressed successfully!")

if __name__ == "__main__":
    resize_logo()
