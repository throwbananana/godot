"""Sokpop 黏土渲染管线的共享底层 (Shared Sokpop clay render pipeline).

三个 build_* 脚本以前各自复制了一份 setup_render_settings / create_clay_mat /
bevel / render_and_clean，导致同一个 bug 要修三遍、风格会慢慢发散。
现在统一到这里，build_* 只保留各自的建模逻辑。

本模块修掉的四个画风问题:
  1. sRGB→linear 色彩空间错配 —— 之前颜色按 sRGB 直觉书写却直接塞进
     scene-linear 的 Base Color, 整体被提亮 + 去饱和 (蓝通道 0.22 → 实际 0.04)。
  2. AgX 视图变换 —— 为写实 HDR 设计, 高光强制向白收敛, 把黏土的色度洗掉了。
     换回 Standard, 靠灯光标定而不是 tonemapper 来控过曝。
  3. 表面毫无不规则性 —— 完美 primitive + 均匀倒角 = 注塑塑料。
     补上 noise→bump 微凹凸、手捏色斑、顶点抖动。
  4. 灯光标定 —— 原来的 point light 在 6~7 单位外只贡献 ~0.03 W/m², 几乎无效,
     实际全靠 sun 2.6 单打独斗。改为 sun + World 环境光为主, point 作塑形。
"""

import bpy
import math
import os

# ---------------------------------------------------------------- 尺寸与画幅常量 (Dimensional Standards)
ORTHO_SCALE_DEFAULT = 3.3       # 默认画幅宽度 (单位)
ORTHO_SCALE_TANK    = 3.6       # 坦克画幅宽度 (单位, 彻底解决前伸炮管与消焰器顶部裁切)
TILE_FULL_BLEED     = 3.34      # 瓦片底板满幅尺寸 (略超 3.30，消除相邻网格 6.4px 黑缝，实现 100% 满幅无缝拼接)
MAX_ASSET_RADIUS    = 1.60      # 中心旋转资源的安全最大半径

# ---------------------------------------------------------------- 色彩空间

def _srgb_channel_to_linear(c):
    """单通道 sRGB → scene-linear。"""
    if c <= 0.04045:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


def srgb_to_linear(col):
    """把按 sRGB 直觉书写的颜色转成 Blender 节点需要的 scene-linear 值。

    alpha 不参与转换。传 None 返回 None, 方便直接套在可选的 emission 上。

    >>> srgb_to_linear((0.98, 0.80, 0.22, 1.0))
    (0.955..., 0.604..., 0.040..., 1.0)
    """
    if col is None:
        return None
    if len(col) == 4:
        r, g, b, a = col
    else:
        r, g, b = col
        a = 1.0
    return (
        _srgb_channel_to_linear(r),
        _srgb_channel_to_linear(g),
        _srgb_channel_to_linear(b),
        a,
    )


# ---------------------------------------------------------------- 场景/渲染

def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


_STYLIZE_GROUP = "SokpopStylize"


def setup_stylize_compositor(levels=0, pixelate=0):
    """合成器风格化。levels = posterize 色阶数 (0 关闭), pixelate = 像素块边长 (0 关闭)。

    为什么是量化而不是"烘焙光照到贴图再 unlit":
    烘焙是为实时 3D 服务的 —— 本管线输出的是预渲染 PNG, 光照本来就固化在图里,
    再走一遍 bake→unlit 会得到几乎相同的图。Sokpop 的手绘感差在明暗的"性质"上:
    连续渐变 vs 分明色阶。posterize 直接作用在这一点上。

    Blender 5.x 的合成器 API 与 4.x 不兼容:
      - scene.node_tree 没了, 改成 scene.compositing_node_group 挂一个
        CompositorNodeTree 节点组
      - 组内仍用 CompositorNodeRLayers 取渲染结果作为源, 出口是 NodeGroupOutput
        (不是已被移除的 CompositorNodeComposite)。接 NodeGroupInput 是错的 ——
        它拿不到渲染结果, 输出会是一张 alpha 全 0 的空图。
      - CompositorNodeMath 被统一成了 ShaderNodeMath; 而 posterize/pixelate
        本身有原生节点, 不需要手搓通道量化链。
    这里只实现 5.x 路径 —— 仓库锁定 Blender 5.2 LTS。
    """
    scene = bpy.context.scene

    old = bpy.data.node_groups.get(_STYLIZE_GROUP)
    if old is not None:
        bpy.data.node_groups.remove(old)

    if not levels and not pixelate:
        scene.compositing_node_group = None
        return

    ng = bpy.data.node_groups.new(_STYLIZE_GROUP, "CompositorNodeTree")
    ng.interface.new_socket("Image", in_out='OUTPUT', socket_type='NodeSocketColor')

    rl = ng.nodes.new('CompositorNodeRLayers')
    rl.location = (-400, 0)
    go = ng.nodes.new('NodeGroupOutput')
    go.location = (400, 0)

    cursor = rl.outputs['Image']
    x = -200

    if pixelate:
        pix = ng.nodes.new('CompositorNodePixelate')
        pix.inputs['Size'].default_value = int(pixelate)
        pix.location = (x, 0)
        ng.links.new(cursor, pix.inputs['Color'])
        cursor = pix.outputs['Color']
        x += 200

    if levels:
        post = ng.nodes.new('CompositorNodePosterize')
        post.inputs['Steps'].default_value = float(levels)
        post.location = (x, 0)
        ng.links.new(cursor, post.inputs['Image'])
        cursor = post.outputs['Image']

    ng.links.new(cursor, go.inputs[0])
    scene.compositing_node_group = ng


def setup_render_settings(rx=256, ry=256, samples=48,
                          posterize_levels=0, pixelate=0):
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    if hasattr(scene, 'cycles'):
        scene.cycles.samples = samples
        scene.cycles.adaptive_threshold = 0.02
    scene.render.resolution_x = rx
    scene.render.resolution_y = ry
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.image_settings.color_depth = '8'
    scene.render.image_settings.compression = 90
    scene.render.film_transparent = True

    # Standard 而不是 AgX: 黏土要的是饱和大色块, 不是写实胶片曲线。
    # 过曝靠下面的灯光标定压住, 不靠 tonemapper 洗色度。
    scene.view_settings.view_transform = 'Standard'
    try:
        scene.view_settings.look = 'None'
    except Exception:
        pass
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0

    # 默认关闭 —— 已提交的资源就是不风格化的版本, 改这里会全量改变画风。
    setup_stylize_compositor(posterize_levels, pixelate)


def create_sokpop_lighting(ortho_scale=3.3, sun_energy=0.9,
                           ambient_strength=0.85):
    """正交顶视相机 + 压平光比的暖阳/环境光/塑形补光。

    光比取向: 环境光为主 (0.85) + 弱主光 (0.9 W/m²)。
    Sokpop 的形体靠轮廓和色块区分, 不靠明暗层次 —— 深光比会把饱和色的暗部一路
    推过 橙→红→黑, 既脏又不像手绘。压平之后暗部仍在同一色相内, 颜色更干净。
    这也是量化 (setup_stylize_compositor) 能不能用的前提: 直接量化一条深渐变
    会切出错误色相的中间带, 压平之后才不会。

    幂等: 会先清掉已有的相机/灯光。clay_ui 的 main() 在同一场景里连调三次本函数
    换分辨率, 旧实现每次都新增一套, 到心形图标时已经有 9 盏灯在照 —— UI 资源
    亮度虚高、饱和度掉到 2% 就是这么来的。
    """
    for obj in list(bpy.data.objects):
        if obj.type in {'CAMERA', 'LIGHT'}:
            bpy.data.objects.remove(obj, do_unlink=True)

    cam_data = bpy.data.cameras.new(name='TopDownCam')
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = ortho_scale
    cam_obj = bpy.data.objects.new('TopDownCam', cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = (0, 0, 10)
    bpy.context.scene.camera = cam_obj

    # 1. 暖阳主灯
    sun_data = bpy.data.lights.new(name='SunKey', type='SUN')
    sun_data.energy = sun_energy
    sun_data.color = srgb_to_linear((1.0, 0.95, 0.88))[:3]
    sun_data.angle = math.radians(12.0)  # 软一点的影, 黏土不要刀切边
    sun_obj = bpy.data.objects.new('SunKey', sun_data)
    bpy.context.collection.objects.link(sun_obj)
    sun_obj.location = (3, -3, 8)
    sun_obj.rotation_euler = (math.radians(38), math.radians(18), math.radians(-32))

    # 2. World 环境光 —— 抬暗部, 避免背光面死黑。
    #    film_transparent 只影响相机直接看到的背景, 不影响它参与照明。
    world = bpy.data.worlds.new("SokpopAmbient")
    world.use_nodes = True
    bg = world.node_tree.nodes.get('Background')
    if bg is not None:
        # 偏冷但别太蓝 —— 太蓝会把黏土暗部染成脏紫色。
        bg.inputs['Color'].default_value = srgb_to_linear((0.70, 0.72, 0.78, 1.0))
        bg.inputs['Strength'].default_value = ambient_strength
    bpy.context.scene.world = world

    # 3. 冷调塑形补光 (能量按平方反比标定过, 旧版 16W 在这个距离等于没开灯)
    fill_data = bpy.data.lights.new(name='FillLight', type='POINT')
    fill_data.energy = 110.0
    fill_data.color = srgb_to_linear((0.90, 0.90, 1.0))[:3]
    fill_data.shadow_soft_size = 2.5
    fill_obj = bpy.data.objects.new('FillLight', fill_data)
    bpy.context.collection.objects.link(fill_obj)
    fill_obj.location = (-4, 4, 6)

    # 4. 背侧轮廓光
    rim_data = bpy.data.lights.new(name='RimLight', type='POINT')
    rim_data.energy = 70.0
    rim_data.color = srgb_to_linear((1.0, 0.97, 0.92))[:3]
    rim_data.shadow_soft_size = 2.0
    rim_obj = bpy.data.objects.new('RimLight', rim_data)
    bpy.context.collection.objects.link(rim_obj)
    rim_obj.location = (0, 5, 4.5)


# ---------------------------------------------------------------- 材质

def create_clay_mat(name, col, roughness=0.76, sss_weight=0.08,
                    emission=None, emission_str=0.0,
                    bump_strength=0.30, mottle=0.08, emission_peak=0.85):
    """黏土材质。col / emission 按 sRGB 书写, 内部转 linear。

    bump_strength: noise→bump 微凹凸, 模拟指纹与捏痕。0 表示关掉。
    mottle:        大尺度色斑强度, 模拟手工调色不均。0 表示关掉。
    emission_peak: 自发光最亮通道的线性上限, 超了就等比压 emission_str。
                   之前 AgX 会把溢出的自发光"接住"压回白色, 换成 Standard 之后
                   emission_str=3.0 会让 VFX 每个像素都有通道撞顶 —— 亮是亮了,
                   色相全丢。传 None 可以关掉钳制。
    """
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    lin_col = srgb_to_linear(col)
    bsdf.inputs['Base Color'].default_value = lin_col
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = 0.0

    if 'Subsurface Weight' in bsdf.inputs:
        bsdf.inputs['Subsurface Weight'].default_value = sss_weight
    elif 'Subsurface' in bsdf.inputs:
        bsdf.inputs['Subsurface'].default_value = sss_weight

    # 手捏色斑: 把基色朝稍暗的同色相偏移一点点, 让大色块不至于死平。
    if mottle > 0.0:
        mottle_noise = nodes.new(type='ShaderNodeTexNoise')
        mottle_noise.inputs['Scale'].default_value = 3.5
        mottle_noise.inputs['Detail'].default_value = 2.0
        mottle_noise.location = (-700, 200)

        shade_col = (
            lin_col[0] * 0.78, lin_col[1] * 0.80, lin_col[2] * 0.86, 1.0
        )

        # Blender 4.0 起 MixRGB 被 ShaderNodeMix 取代, 5.x 可能已经彻底移除。
        # ShaderNodeMix 的同名 socket 有 float/vector/color 三套, 只能按索引取:
        # 0=Factor(float), 6=A(color), 7=B(color); 输出 2=Result(color)。
        mix = None
        try:
            mix = nodes.new(type='ShaderNodeMix')
            mix.data_type = 'RGBA'
            mix.blend_type = 'MIX'
            mix.inputs[0].default_value = mottle
            mix.inputs[6].default_value = lin_col
            mix.inputs[7].default_value = shade_col
            fac_in, col_out = mix.inputs[0], mix.outputs[2]
        except Exception:
            if mix is not None:
                nodes.remove(mix)
            mix = nodes.new(type='ShaderNodeMixRGB')
            mix.blend_type = 'MIX'
            mix.inputs['Fac'].default_value = mottle
            mix.inputs['Color1'].default_value = lin_col
            mix.inputs['Color2'].default_value = shade_col
            fac_in, col_out = mix.inputs['Fac'], mix.outputs['Color']

        mix.location = (-450, 200)

        # 噪声直接接 Fac 会顶掉上面设的 default_value, 等于 100% 色斑。
        # 先乘以 mottle 把幅度压回预期强度。
        mottle_gain = nodes.new(type='ShaderNodeMath')
        mottle_gain.operation = 'MULTIPLY'
        mottle_gain.inputs[1].default_value = mottle
        mottle_gain.location = (-580, 200)

        links.new(mottle_noise.outputs['Fac'], mottle_gain.inputs[0])
        links.new(mottle_gain.outputs['Value'], fac_in)
        links.new(col_out, bsdf.inputs['Base Color'])

    # 指纹/捏痕微凹凸
    if bump_strength > 0.0:
        bump_noise = nodes.new(type='ShaderNodeTexNoise')
        bump_noise.inputs['Scale'].default_value = 20.0
        bump_noise.inputs['Detail'].default_value = 3.0
        bump_noise.inputs['Roughness'].default_value = 0.55
        bump_noise.location = (-700, -150)

        bump = nodes.new(type='ShaderNodeBump')
        bump.inputs['Strength'].default_value = bump_strength
        bump.inputs['Distance'].default_value = 0.035
        bump.location = (-450, -150)

        links.new(bump_noise.outputs['Fac'], bump.inputs['Height'])
        links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])

    if emission and emission_str > 0:
        if 'Emission Color' in bsdf.inputs:
            lin_em = srgb_to_linear(emission)
            if emission_peak is not None:
                peak = max(lin_em[0], lin_em[1], lin_em[2])
                if peak * emission_str > emission_peak:
                    emission_str = emission_peak / max(peak, 1e-6)
            bsdf.inputs['Emission Color'].default_value = lin_em
            bsdf.inputs['Emission Strength'].default_value = emission_str

    out = nodes.new(type='ShaderNodeOutputMaterial')
    out.location = (300, 0)
    links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    return mat


# ---------------------------------------------------------------- 几何

_jitter_seed = [0]


def reset_jitter_seed(value=0):
    """让整批渲染可复现 —— main() 开头调一次。"""
    _jitter_seed[0] = value


def apply_clay_jitter(obj, strength=0.02):
    """轻微随机化顶点位置, 让形体像手捏的而不是数学生成的。

    在倒角修改器之前作用于基础网格, 所以低模上是"整体捏歪"而不是表面噪点。
    """
    if strength <= 0.0:
        return
    _jitter_seed[0] += 1
    try:
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.transform.vertex_random(
            offset=strength, uniform=0.55, normal=0.0, seed=_jitter_seed[0]
        )
        bpy.ops.object.mode_set(mode='OBJECT')
    except Exception:
        # 个别非网格物体或上下文异常时不要中断整批渲染
        if bpy.context.object and bpy.context.object.mode != 'OBJECT':
            bpy.ops.object.mode_set(mode='OBJECT')


def apply_uniform_clay_bevel(obj, width=0.12, segments=4, jitter=0.018):
    """统一倒角 + 手捏抖动。jitter=0 可关掉抖动 (发光/UI 细节件)。"""
    bpy.context.view_layer.objects.active = obj
    try:
        obj.select_set(True)
    except Exception:
        pass
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    apply_clay_jitter(obj, strength=jitter)
    bpy.ops.object.shade_smooth()
    mod = obj.modifiers.new(name="Bevel", type='BEVEL')
    mod.width = width
    mod.segments = segments
    mod.limit_method = 'ANGLE'
    mod.angle_limit = math.radians(22)


# ---------------------------------------------------------------- 输出

def render_and_clean(objects, out_path, label="Rendered"):
    bpy.context.scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    for obj in objects:
        try:
            bpy.data.objects.remove(obj, do_unlink=True)
        except Exception:
            pass
    print(f"{label}: {os.path.basename(out_path)}")
