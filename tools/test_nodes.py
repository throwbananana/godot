import bpy

def test_nodes():
    mat = bpy.data.materials.new(name="TestRichTexture")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    
    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    out = nodes.new(type='ShaderNodeOutputMaterial')
    noise = nodes.new(type='ShaderNodeTexNoise')
    bump = nodes.new(type='ShaderNodeBump')
    
    mat.node_tree.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    mat.node_tree.links.new(noise.outputs['Fac'], bump.inputs['Height'])
    mat.node_tree.links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
    print("NODE_SETUP_SUCCESSFUL")

test_nodes()
