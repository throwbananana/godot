import os
import glob
from PIL import Image, ImageFilter
import numpy as np

def cut_outer_background(img_path, out_path, tolerance=30, feather=2):
    im = Image.open(img_path).convert("RGBA")
    w, h = im.size
    arr = np.array(im, dtype=np.float32)

    # Sample background color from all four corners
    corners = np.vstack([
        arr[0:15, 0:15, :3].reshape(-1, 3),
        arr[0:15, w-15:w, :3].reshape(-1, 3),
        arr[h-15:h, 0:15, :3].reshape(-1, 3),
        arr[h-15:h, w-15:w, :3].reshape(-1, 3),
    ])
    bg_color = np.median(corners, axis=0)
    
    # Distance from background
    diff = np.linalg.norm(arr[:, :, :3] - bg_color, axis=2)
    
    # Mask: 0 where close to background, 255 where foreground
    mask = np.clip((diff - tolerance) / max(1.0, tolerance * 0.8) * 255.0, 0, 255).astype(np.uint8)
    
    # To avoid cutting interior pixels that happen to match bg color,
    # flood fill from the edges to only remove connected background
    mask_im = Image.fromarray(mask, mode="L")
    
    # Connected component / floodfill background
    # Invert so background is bright
    bg_seed = Image.eval(mask_im, lambda p: 255 if p < 40 else 0)
    from PIL import ImageDraw
    ImageDraw.floodfill(bg_seed, (0, 0), 128)
    ImageDraw.floodfill(bg_seed, (w - 1, 0), 128)
    ImageDraw.floodfill(bg_seed, (0, h - 1), 128)
    ImageDraw.floodfill(bg_seed, (w - 1, h - 1), 128)
    
    # Only pixels connected to border (value 128) are true background
    bg_mask_arr = np.array(bg_seed)
    is_true_bg = (bg_mask_arr == 128)
    
    alpha = np.array(im.split()[3])
    alpha[is_true_bg] = 0
    
    # Feather edges slightly
    alpha_im = Image.fromarray(alpha, mode="L").filter(ImageFilter.GaussianBlur(radius=feather))
    im.putalpha(alpha_im)
    
    # Auto-crop bounding box with padding
    bbox = im.getbbox()
    if bbox:
        pad = 8
        crop_box = (
            max(0, bbox[0] - pad),
            max(0, bbox[1] - pad),
            min(w, bbox[2] + pad),
            min(h, bbox[3] + pad)
        )
        im = im.crop(crop_box)
        
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    im.save(out_path, "PNG")
    print(f"[OK] Processed {os.path.basename(out_path)}: size={im.size}")

def slice_switch_widgets(widgets_path, out_dir):
    im = Image.open(widgets_path).convert("RGBA")
    w, h = im.size
    
    # Slices:
    # Top-Left: Unchecked Box ~ (80, 80, 480, 480)
    # Top-Right: Checked Box ~ (540, 80, 940, 480)
    # Bottom-Left: Slider Track + Knob ~ (60, 520, 560, 880)
    # Bottom-Right: Toggle Switch ~ (620, 520, 880, 880)
    
    cuts = {
        "ui_clay_checkbox_unchecked.png": (100, 90, 470, 460),
        "ui_clay_checkbox_checked.png": (550, 90, 920, 460),
        "ui_clay_slider_widget.png": (70, 530, 570, 860),
        "ui_clay_toggle_switch.png": (630, 530, 860, 860)
    }
    
    for fname, box in cuts.items():
        sub = im.crop(box)
        sub_path = os.path.join(out_dir, fname)
        # Background is uniform grey ~ (184, 185, 194)
        sub_arr = np.array(sub, dtype=np.float32)
        corners = np.vstack([
            sub_arr[0:10, 0:10, :3].reshape(-1, 3),
            sub_arr[0:10, -10:, :3].reshape(-1, 3),
            sub_arr[-10:, 0:10, :3].reshape(-1, 3),
            sub_arr[-10:, -10:, :3].reshape(-1, 3),
        ])
        bg = np.median(corners, axis=0)
        diff = np.linalg.norm(sub_arr[:, :, :3] - bg, axis=2)
        alpha = np.clip((diff - 25) / 20.0 * 255.0, 0, 255).astype(np.uint8)
        alpha_im = Image.fromarray(alpha, mode="L").filter(ImageFilter.GaussianBlur(1.0))
        sub.putalpha(alpha_im)
        sub.save(sub_path, "PNG")
        print(f"[OK] Sliced widget {fname}: size={sub.size}")

def main():
    brain_dir = r"C:\Users\123\.gemini\antigravity-cli\brain\adda25c7-006a-42b6-81c3-b3af3cdcd61f"
    out_dir = r"G:\Users\123\Documents\GitHub\godot\assets\sprites\ui"
    
    # 1. Dialog panel
    panel_src = glob.glob(os.path.join(brain_dir, "ui_clay_dialog_panel_*.jpg"))
    if panel_src:
        cut_outer_background(panel_src[0], os.path.join(out_dir, "ui_clay_dialog_panel.png"), tolerance=35)
        
    # 2. HUD sidepanel
    hud_src = glob.glob(os.path.join(brain_dir, "ui_clay_hud_sidepanel_*.jpg"))
    if hud_src:
        cut_outer_background(hud_src[0], os.path.join(out_dir, "ui_clay_hud_sidepanel.png"), tolerance=30)
        
    # 3. Card plate
    card_src = glob.glob(os.path.join(brain_dir, "ui_clay_card_plate_*.jpg"))
    if card_src:
        cut_outer_background(card_src[0], os.path.join(out_dir, "ui_clay_card_plate.png"), tolerance=28)
        
    # 4. Switch widgets
    widget_src = glob.glob(os.path.join(brain_dir, "ui_clay_switch_widgets_*.jpg"))
    if widget_src:
        slice_switch_widgets(widget_src[0], out_dir)

if __name__ == "__main__":
    main()
