import sys
from PIL import Image

def scale_image(input_path, output_path, scale_factor=2):
    """
    Scale an image by duplicating each pixel into a square of pixels.
    
    Args:
        input_path (str): Path to the input image
        output_path (str): Path to save the scaled image
        scale_factor (int): Factor by which to scale the image (default: 2)
    """
    try:
        # Open the original image
        original_img = Image.open(input_path)
        width, height = original_img.size
        
        # Convert to RGBA if it's a palette image
        if original_img.mode == 'P':
            original_img = original_img.convert('RGBA')
        
        # Create a new image with scaled dimensions
        scaled_img = Image.new(original_img.mode, (width * scale_factor, height * scale_factor))
        
        # If the original had a palette, copy it to the new image
        if hasattr(original_img, 'palette') and original_img.palette:
            scaled_img.palette = original_img.palette.copy()
        
        # Copy each pixel to a scale_factor x scale_factor square in the new image
        for y in range(height):
            for x in range(width):
                pixel = original_img.getpixel((x, y))
                # Fill a square with this pixel color
                for dy in range(scale_factor):
                    for dx in range(scale_factor):
                        scaled_img.putpixel((x * scale_factor + dx, y * scale_factor + dy), pixel)
        
        # Save the scaled image
        scaled_img.save(output_path)
        print(f"Image scaled and saved to {output_path}")
        return True
    except Exception as e:
        print(f"Error scaling image: {e}")
        return False

def duplicate_image_horizontally(input_path, output_path, copies=21):
    """
    Create a new image with multiple copies of the original image placed horizontally.
    
    Args:
        input_path (str): Path to the input image
        output_path (str): Path to save the duplicated image
        copies (int): Number of copies to place horizontally (default: 21)
    """
    try:
        # Open the original image
        original_img = Image.open(input_path)
        width, height = original_img.size
        
        # Convert to RGBA if it's a palette image
        if original_img.mode == 'P':
            original_img = original_img.convert('RGBA')
        
        # Create a new image with width multiplied by the number of copies
        duplicated_img = Image.new(original_img.mode, (width * copies, height))
        
        # If the original had a palette, copy it to the new image
        if hasattr(original_img, 'palette') and original_img.palette:
            duplicated_img.palette = original_img.palette.copy()
        
        # Paste the original image multiple times horizontally
        for i in range(copies):
            duplicated_img.paste(original_img, (i * width, 0))
        
        # Save the duplicated image
        duplicated_img.save(output_path)
        print(f"Image duplicated {copies} times horizontally and saved to {output_path}")
        return True
    except Exception as e:
        print(f"Error duplicating image: {e}")
        return False

def stack_images_vertically(input_paths, output_path):
    """
    Create a new image with multiple images stacked vertically.
    
    Args:
        input_paths (list): List of paths to the input images
        output_path (str): Path to save the stacked image
    """
    try:
        if not input_paths:
            raise ValueError("No input paths provided")
            
        # Open all images and check they have the same width
        images = []
        for path in input_paths:
            img = Image.open(path)
            if img.mode == 'P':
                img = img.convert('RGBA')
            images.append(img)
        
        # Get dimensions
        width = images[0].width
        total_height = sum(img.height for img in images)
        
        # Create a new image with combined height
        stacked_img = Image.new(images[0].mode, (width, total_height))
        
        # Paste each image at the appropriate vertical position
        current_y = 0
        for img in images:
            stacked_img.paste(img, (0, current_y))
            current_y += img.height
        
        # Save the stacked image
        stacked_img.save(output_path)
        print(f"Images stacked vertically and saved to {output_path}")
        return True
    except Exception as e:
        print(f"Error stacking images: {e}")
        return False

if __name__ == "__main__":
    input_path = "minecraft-main/assets/1x/bossSingleSkeleton.png"
    scale_factor = 2
    copies = 21

    bosses = [
        "Skeleton",
        "Zombie",
        "Creeper",
        "Enderman",
        "Spider",
        "Blaze",
        "Drowned",
        "Stray",
        "Husk",
        "Magmacube"
    ]

    for boss in bosses:
        scale_image(f"minecraft-main/assets/1x/boss{boss}Single.png", f"minecraft-main/assets/2x/boss{boss}Single.png", scale_factor)
        duplicate_image_horizontally(f"minecraft-main/assets/1x/boss{boss}Single.png", f"minecraft-main/assets/1x/boss{boss}.png", copies)
        duplicate_image_horizontally(f"minecraft-main/assets/2x/boss{boss}Single.png", f"minecraft-main/assets/2x/boss{boss}.png", copies)

    stack_images_vertically(
        [f"minecraft-main/assets/1x/boss{boss}.png" for boss in bosses],
        'minecraft-main/assets/1x/blinds.png'
    )

    stack_images_vertically(
        [f"minecraft-main/assets/2x/boss{boss}.png" for boss in bosses],
        'minecraft-main/assets/2x/blinds.png'
    )
