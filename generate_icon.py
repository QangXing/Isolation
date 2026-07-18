from PIL import Image, ImageDraw
import os

sizes = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
}

def draw_icon(size):
    img = Image.new('RGBA', (size, size), (255, 255, 255, 0))
    draw = ImageDraw.Draw(img)
    
    # Background rounded rect (white)
    radius = int(size * 0.234)  # ~120/512
    draw.rounded_rectangle(
        [0, 0, size - 1, size - 1],
        radius=radius,
        fill=(255, 255, 255, 255)
    )
    
    # Inner border 1
    margin1 = int(size * 0.125)
    radius1 = int(size * 0.188)
    draw.rounded_rectangle(
        [margin1, margin1, size - margin1 - 1, size - margin1 - 1],
        radius=radius1,
        outline=(232, 232, 232, 255),
        width=max(1, int(size * 0.023))
    )
    
    # Inner border 2
    margin2 = int(size * 0.25)
    radius2 = int(size * 0.125)
    draw.rounded_rectangle(
        [margin2, margin2, size - margin2 - 1, size - margin2 - 1],
        radius=radius2,
        outline=(240, 240, 240, 255),
        width=max(1, int(size * 0.016))
    )
    
    return img

base = '/workspace/isolation/android/app/src/main/res'
for name, size in sizes.items():
    folder = os.path.join(base, f'mipmap-{name}')
    os.makedirs(folder, exist_ok=True)
    icon = draw_icon(size)
    icon.save(os.path.join(folder, 'ic_launcher.png'), 'PNG')
    print(f'Generated {folder}/ic_launcher.png')

# Also generate a 512x512 store icon
folder = '/workspace/isolation/android/app/src/main/res/mipmap-xxxhdpi'
icon = draw_icon(512)
icon.save(os.path.join(folder, 'ic_launcher_foreground.png'), 'PNG')
print(f'Generated {folder}/ic_launcher_foreground.png')
