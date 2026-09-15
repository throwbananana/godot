extends SceneTree

func _init():
    print('[CAPTURE] Starting screenshot automated capture...')
    var scenes = [
        {'path': 'res://scenes/title_screen.tscn', 'name': 'screenshot_1_title.png', 'wait': 0.5},
        {'path': 'res://scenes/spire_map.tscn', 'name': 'screenshot_2_spire_map.png', 'wait': 0.5},
        {'path': 'res://scenes/main.tscn', 'name': 'screenshot_3_battle.png', 'wait': 0.8}
    ]
    
    var out_dir = 'G:/Users/123/Documents/GitHub/godot/build/screenshots'
    DirAccess.make_dir_recursive_absolute(out_dir)
    
    for item in scenes:
        var packed = load(item.path)
        if not packed:
            continue
        var inst = packed.instantiate()
        root.add_child(inst)
        
        # Wait a few frames
        for f in range(15):
            await process_frame
            
        var img = root.get_texture().get_image()
        if img:
            var save_path = out_dir + '/' + item.name
            img.save_png(save_path)
            print('[CAPTURE] Saved: ' + save_path)
        inst.queue_free()
        await process_frame
        
    print('[CAPTURE] Done all screenshots!')
    quit()
