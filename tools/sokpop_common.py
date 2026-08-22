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

# 道具/小建筑画幅。这个数是考古出来的, 不是拍的:
# refine_all_assets.py / refine_buildings_and_tanks.py 一直用 ORTHO_SCALE_DEFAULT
# 渲这 8 个资源 (star/bomb/shovel/clock/helmet/life/repair_station/turret_gun),
# 但仓库里已提交的版本明显更大。量了 alpha 包围盒: 八张全部等比小了 0.817~0.824,
# 纵横比误差 <=1% —— 纯画幅差, 几何没变。正交相机下像素尺寸与 ortho_scale 成反比,
# 3.3 * 0.82 = 2.706, 也就是当初那个已被删除的脚本用的是 2.7。改回 2.7 之后,
# 八张的包围盒与已提交版本逐像素一致 (比值 1.000, 纵横比差 0.0%)。
# 结论: 这 8 个资源的正确画幅是 2.7, refine_* 用 3.3 是"四代合并"时丢失的信息。
ORTHO_SCALE_PROP    = 2.7       # 道具/小建筑画幅 (比默认更紧, 让道具在 48px 下更满)

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
    clear_material_cache()


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


def setup_render_settings(rx=256, ry=256, samples=28,
                          posterize_levels=0, pixelate=0):
    # 这里是查漏的最佳位置: 各脚本都是 clear_scene() -> setup_render_settings()
    # 开批, 中途切分辨率时上一批也已被 render_and_clean() 删干净, 所以正常流程
    # 走到这一句时场景必然是空的, 不会误报。
    warn_if_stray_meshes("setup_render_settings")

    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    if hasattr(scene, 'cycles'):
        scene.cycles.samples = samples
        scene.cycles.adaptive_threshold = 0.025
        # 优化光线弹射深度 (Light Bounces Pruning) —— 2D正交精灵无玻璃折射与体积雾
        scene.cycles.max_bounces = 4
        scene.cycles.diffuse_bounces = 2
        scene.cycles.glossy_bounces = 2
        scene.cycles.transmission_bounces = 0
        scene.cycles.volume_bounces = 0
        scene.cycles.transparent_max_bounces = 6
        try:
            scene.cycles.use_denoising = True
            scene.cycles.denoiser = 'OPENIMAGEDENOISE'
        except Exception:
            pass

    scene.render.resolution_x = rx
    scene.render.resolution_y = ry
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.image_settings.color_depth = '8'
    scene.render.image_settings.compression = 90
    scene.render.film_transparent = True

    # Standard 而不是 AgX: 黏土要的是饱和大色块, 不是写实胶片曲线。
    scene.view_settings.view_transform = 'Standard'
    try:
        scene.view_settings.look = 'None'
    except Exception:
        pass
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0

    setup_stylize_compositor(posterize_levels, pixelate)


def warn_if_stray_meshes(context=""):
    """场景里若已有 mesh 就告警 —— 渲染事故的自曝装置。

    create_sokpop_lighting() 只清相机和灯, 不清 mesh; render_and_clean() 也只删
    调用方传进来的那一批。所以少调一次 clear_scene(), Blender 出厂场景的默认
    立方体就会静默地挡在镜头前, 把整批资源渲成同一块灰方块 —— 这正是
    build_ui_character_art_replacements.py 的九个 UI 图标发生过的事, 而且因为
    渲染本身"成功"了, 一直到有人去量像素方差才被发现。

    不抛异常: 有的脚本会在一批对象还在场时切分辨率重新布光, 那是合法用法。
    这里只负责让异常状态在 stdout 上留下痕迹。
    """
    strays = [o.name for o in bpy.data.objects if o.type == 'MESH']
    if strays:
        shown = ", ".join(strays[:6]) + (" ..." if len(strays) > 6 else "")
        print(f"[WARN] 场景中已存在 {len(strays)} 个 mesh{(' (' + context + ')') if context else ''}: {shown}")
        print("[WARN] 若这不是有意为之, 说明漏了 clear_scene() —— 渲染结果可能被遮挡。")
    return strays


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

    cam_data = bpy.data.cameras.new('OrthoCam')
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = ortho_scale
    cam_data.clip_start = 0.1
    cam_data.clip_end = 100.0

    cam_obj = bpy.data.objects.new('Camera', cam_data)
    bpy.context.collection.objects.link(cam_obj)
    bpy.context.scene.camera = cam_obj
    cam_obj.location = (0, 0, 10)
    cam_obj.rotation_euler = (0, 0, 0)

    # 1. 暖调主日光
    sun_data = bpy.data.lights.new('Sun', 'SUN')
    sun_data.energy = sun_energy
    sun_data.color = srgb_to_linear((1.0, 0.96, 0.88))[:3]
    sun_obj = bpy.data.objects.new('SunLight', sun_data)
    bpy.context.collection.objects.link(sun_obj)
    sun_obj.rotation_euler = (math.radians(35), math.radians(20), math.radians(-35))

    # 2. 漫反射环境光
    world = bpy.context.scene.world
    if world is None:
        world = bpy.data.worlds.new("SokpopWorld")
        bpy.context.scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get('Background')
    if bg:
        # 偏冷但别太蓝 —— 太蓝会把黏土暗部染成脏紫色
        bg.inputs['Color'].default_value = srgb_to_linear((0.70, 0.72, 0.78, 1.0))
        bg.inputs['Strength'].default_value = ambient_strength

    # 3. 柔和正面塑形补光 (Key Fill)
    key_data = bpy.data.lights.new('KeyFill', 'POINT')
    key_data.energy = 110.0
    key_data.color = srgb_to_linear((1.0, 0.97, 0.93))[:3]
    key_data.shadow_soft_size = 2.0
    key_obj = bpy.data.objects.new('KeyLight', key_data)
    bpy.context.collection.objects.link(key_obj)
    key_obj.location = (-2.5, -4.0, 5.0)

    # 4. 背面浅冷色轮廓光 (Rim Light)
    rim_data = bpy.data.lights.new('RimFill', 'POINT')
    rim_data.energy = 70.0
    rim_data.color = srgb_to_linear((0.95, 0.97, 1.0))[:3]
    rim_data.shadow_soft_size = 2.0
    rim_obj = bpy.data.objects.new('RimLight', rim_data)
    bpy.context.collection.objects.link(rim_obj)
    rim_obj.location = (0, 5, 4.5)


# ---------------------------------------------------------------- 材质缓存与构造

_material_cache = {}

def clear_material_cache():
    _material_cache.clear()

def create_clay_mat(name, col, roughness=0.76, sss_weight=0.08,
                    emission=None, emission_str=0.0,
                    bump_strength=0.28, mottle=0.08, emission_peak=0.85):
    """黏土材质（带 Material Data-Block 缓存复用与微观指纹印记）。"""
    cache_key = f"{name}_{col}_{roughness}_{sss_weight}_{emission}_{emission_str}_{bump_strength}_{mottle}_{emission_peak}"
    if cache_key in _material_cache and _material_cache[cache_key].name in bpy.data.materials:
        return _material_cache[cache_key]

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

    # 手捏色斑: 把基色朝稍暗的同色相偏移一点点
    if mottle > 0.0:
        mottle_noise = nodes.new(type='ShaderNodeTexNoise')
        mottle_noise.inputs['Scale'].default_value = 3.5
        mottle_noise.inputs['Detail'].default_value = 2.0
        mottle_noise.location = (-700, 200)

        shade_col = (lin_col[0] * 0.85, lin_col[1] * 0.85, lin_col[2] * 0.85, lin_col[3])
        try:
            mix = nodes.new(type='ShaderNodeMix')
            mix.data_type = 'RGBA'
            mix.blend_type = 'MIX'
            mix.inputs[0].default_value = mottle
            mix.inputs[6].default_value = lin_col
            mix.inputs[7].default_value = shade_col
            fac_in, col_out = mix.inputs[0], mix.outputs[2]
        except Exception:
            mix = nodes.new(type='ShaderNodeMixRGB')
            mix.blend_type = 'MIX'
            mix.inputs['Fac'].default_value = mottle
            mix.inputs['Color1'].default_value = lin_col
            mix.inputs['Color2'].default_value = shade_col
            fac_in, col_out = mix.inputs['Fac'], mix.outputs['Color']

        mix.location = (-450, 200)
        mottle_gain = nodes.new(type='ShaderNodeMath')
        mottle_gain.operation = 'MULTIPLY'
        mottle_gain.inputs[1].default_value = mottle
        mottle_gain.location = (-580, 200)

        links.new(mottle_noise.outputs['Fac'], mottle_gain.inputs[0])
        links.new(mottle_gain.outputs['Value'], fac_in)
        links.new(col_out, bsdf.inputs['Base Color'])

    # 微观黏土指纹与捏痕凹凸
    if bump_strength > 0.0:
        bump_noise = nodes.new(type='ShaderNodeTexNoise')
        bump_noise.inputs['Scale'].default_value = 22.0
        bump_noise.inputs['Detail'].default_value = 3.0
        bump_noise.inputs['Roughness'].default_value = 0.55
        bump_noise.location = (-700, -150)

        bump = nodes.new(type='ShaderNodeBump')
        bump.inputs['Strength'].default_value = bump_strength
        bump.inputs['Distance'].default_value = 0.035
        bump.location = (-450, -150)

        links.new(bump_noise.outputs['Fac'], bump.inputs['Height'])
        links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])

    # 自发光
    if emission is not None:
        lin_em = srgb_to_linear(emission)
        if 'Emission Color' in bsdf.inputs:
            if emission_peak is not None:
                peak = max(lin_em[0], lin_em[1], lin_em[2])
                if peak * emission_str > emission_peak:
                    emission_str = emission_peak / max(peak, 1e-6)
            bsdf.inputs['Emission Color'].default_value = lin_em
            bsdf.inputs['Emission Strength'].default_value = emission_str

    out = nodes.new(type='ShaderNodeOutputMaterial')
    out.location = (300, 0)
    links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])

    _material_cache[cache_key] = mat
    return mat


# ---------------------------------------------------------------- 几何与快速抖动

_jitter_seed = [0]

def reset_jitter_seed(value=0):
    """让整批渲染可复现 —— main() 开头调一次。"""
    _jitter_seed[0] = value

def apply_clay_jitter(obj, strength=0.016):
    """直接在 Object 模式下对网格顶点进行手捏轻微形变，零模式切换开销。"""
    if strength <= 0.0 or not obj or obj.type != 'MESH':
        return
    _jitter_seed[0] += 1
    import random
    rng = random.Random(_jitter_seed[0])
    mesh = obj.data
    for v in mesh.vertices:
        v.co.x += rng.uniform(-strength, strength)
        v.co.y += rng.uniform(-strength, strength)
        v.co.z += rng.uniform(-strength * 0.6, strength * 0.6)
    mesh.update()


def apply_uniform_clay_bevel(obj, width=0.10, segments=3, jitter=0.014):
    """统一倒角 + 手捏抖动。jitter=0 可关掉抖动。"""
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


# ---------------------------------------------------------------- 输出与内存清理

def purge_orphans():
    try:
        bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    except Exception:
        pass

def render_and_clean(objects, out_path, label="Rendered"):
    bpy.context.scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    for obj in objects:
        try:
            bpy.data.objects.remove(obj, do_unlink=True)
        except Exception:
            pass
    print(f"{label}: {os.path.basename(out_path)}")
