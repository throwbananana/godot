import os
import glob
from PIL import Image, ImageFilter, ImageDraw
import numpy as np

brain_dir = r"C:\Users\123\.gemini\antigravity-cli\brain\adda25c7-006a-42b6-81c3-b3af3cdcd61f"
out_dir = r"G:\Users\123\Documents\GitHub\godot\assets\sprites\ui"

def make_transparent_white_bg(im, tolerance=25, feather=1.5):
    arr = np.array(im.convert("RGBA"), dtype=np.float32)
    w, h = im.size
    # white bg distance
    diff = np.linalg.norm(arr[:, :, :3] - np.array([255.0, 255.0, 255.0]), axis=2)
    # also sample corners
    corners = np.vstack([
        arr[0:10, 0:10, :3].reshape(-1, 3),
        arr[0:10, -10:, :3].reshape(-1, 3),
        arr[-10:, 0:10, :3].reshape(-1, 3),
        arr[-10:, -10:, :3].reshape(-1, 3),
    ])
    bg = np.median(corners, axis=0)
    diff2 = np.linalg.norm(arr[:, :, :3] - bg, axis=2)
    dist = np.minimum(diff, diff2)
    
    alpha = np.clip((dist - tolerance) / max(1.0, tolerance * 0.8) * 255.0, 0, 255).astype(np.uint8)
    alpha_im = Image.fromarray(alpha, mode="L")
    
    # Floodfill from edges to only remove border-connected white
    bg_seed = Image.eval(alpha_im, lambda p: 255 if p < 40 else 0)
    ImageDraw.floodfill(bg_seed, (0, 0), 128)
    ImageDraw.floodfill(bg_seed, (w - 1, 0), 128)
    ImageDraw.floodfill(bg_seed, (0, h - 1), 128)
    ImageDraw.floodfill(bg_seed, (w - 1, h - 1), 128)
    
    is_true_bg = (np.array(bg_seed) == 128)
    alpha_arr = np.array(im.split()[3] if len(im.split()) == 4 else Image.new("L", (w, h), 255))
    alpha_arr[is_true_bg] = 0
    
    final_alpha = Image.fromarray(alpha_arr, mode="L").filter(ImageFilter.GaussianBlur(feather))
    res = im.convert("RGBA")
    res.putalpha(final_alpha)
    return res

# 1. Subpanel tray
p_files = glob.glob(os.path.join(brain_dir, "ui_clay_subpanel_tray_*.jpg"))
if p_files:
    im = Image.open(p_files[0])
    trans = make_transparent_white_bg(im, tolerance=25)
    bbox = trans.getbbox()
    if bbox:
        trans = trans.crop(bbox)
    trans = trans.resize((480, 360), Image.Resampling.LANCZOS)
    trans.save(os.path.join(out_dir, "ui_clay_subpanel_tray.png"), "PNG")
    print("Saved ui_clay_subpanel_tray.png", trans.size)

# 2. Tab buttons
tab_files = glob.glob(os.path.join(brain_dir, "ui_clay_tab_buttons_*.jpg"))
if tab_files:
    im = Image.open(tab_files[0])
    w, h = im.size
    # top half: active tab (approx y=50..420)
    top_im = im.crop((0, 30, w, h // 2 + 20))
    top_trans = make_transparent_white_bg(top_im, tolerance=20)
    bbox1 = top_trans.getbbox()
    if bbox1:
        top_trans = top_trans.crop(bbox1)
    top_trans = top_trans.resize((240, 64), Image.Resampling.LANCZOS)
    top_trans.save(os.path.join(out_dir, "ui_clay_tab_active.png"), "PNG")
    print("Saved ui_clay_tab_active.png", top_trans.size)

    # bottom half: inactive tab (approx y=420..820)
    bot_im = im.crop((0, h // 2 - 20, w, h - 30))
    bot_trans = make_transparent_white_bg(bot_im, tolerance=20)
    bbox2 = bot_trans.getbbox()
    if bbox2:
        bot_trans = bot_trans.crop(bbox2)
    bot_trans = bot_trans.resize((240, 64), Image.Resampling.LANCZOS)
    bot_trans.save(os.path.join(out_dir, "ui_clay_tab_inactive.png"), "PNG")
    print("Saved ui_clay_tab_inactive.png", bot_trans.size)

# 3. Slider kit
slider_files = glob.glob(os.path.join(brain_dir, "ui_clay_slider_kit_*.jpg"))
if slider_files:
    im = Image.open(slider_files[0])
    w, h = im.size
    # track: middle strip
    # round knob: bottom right (x=670..900, y=630..870)
    knob_im = im.crop((660, 620, 910, 880))
    knob_trans = make_transparent_white_bg(knob_im, tolerance=30)
    bbox_k = knob_trans.getbbox()
    if bbox_k:
        knob_trans = knob_trans.crop(bbox_k)
    knob_trans = knob_trans.resize((36, 36), Image.Resampling.LANCZOS)
    knob_trans.save(os.path.join(out_dir, "ui_clay_slider_grabber.png"), "PNG")
    print("Saved ui_clay_slider_grabber.png", knob_trans.size)

    # track without the knob: x=250..980, y=410..590 or full track
    track_im = im.crop((40, 410, 980, 590))
    track_trans = make_transparent_white_bg(track_im, tolerance=30)
    bbox_t = track_trans.getbbox()
    if bbox_t:
        track_trans = track_trans.crop(bbox_t)
    track_trans = track_trans.resize((320, 36), Image.Resampling.LANCZOS)
    track_trans.save(os.path.join(out_dir, "ui_clay_slider_track.png"), "PNG")
    print("Saved ui_clay_slider_track.png", track_trans.size)
