import bpy

def test_bevel():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0,0,0))
    cube = bpy.context.active_object
    mod = cube.modifiers.new(name="Bevel", type='BEVEL')
    mod.width = 0.1
    mod.segments = 3
    bpy.ops.object.shade_smooth()
    print("BEVEL_MODIFIER_OK")

test_bevel()
