import bpy
import math
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in locals() else os.getcwd()
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

# 渲染管线 (色彩空间/视图变换/灯光标定/黏土材质/倒角抖动) 统一在 sokpop_common,
# 本文件只负责建模。改画风请改 sokpop_common, 不要在这里再复制一份。
from sokpop_common import (  # noqa: E402
    srgb_to_linear,
    clear_scene,
    setup_render_settings,
    create_sokpop_lighting,
    create_clay_mat,
    apply_uniform_clay_bevel,
    reset_jitter_seed,
    render_and_clean,
    ORTHO_SCALE_DEFAULT,
    ORTHO_SCALE_TANK,
    TILE_FULL_BLEED,
    TILE_PLATE_BLEED,
    MAX_ASSET_RADIUS,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_TANKS = os.path.join(PROJECT_DIR, "assets", "sprites", "tanks")
SPRITES_TILES = os.path.join(PROJECT_DIR, "assets", "sprites", "tiles")
SPRITES_EFFECTS = os.path.join(PROJECT_DIR, "assets", "sprites", "effects")
SPRITES_POWERUPS = os.path.join(PROJECT_DIR, "assets", "sprites", "powerups")
SPRITES_BUILDINGS = os.path.join(PROJECT_DIR, "assets", "sprites", "buildings")
SPRITES_MAP = os.path.join(PROJECT_DIR, "assets", "sprites", "map")
SPRITES_UI = os.path.join(PROJECT_DIR, "assets", "sprites", "ui")
BLENDER_SAVE = os.path.join(PROJECT_DIR, "assets", "blender", "tank_battle_assets.blend")

for folder in [SPRITES_TANKS, SPRITES_TILES, SPRITES_EFFECTS, SPRITES_POWERUPS, SPRITES_BUILDINGS, SPRITES_MAP, SPRITES_UI]:
    os.makedirs(folder, exist_ok=True)

def create_3d_star(r_out=1.15, r_in=0.52, depth=0.30, z_pos=0.0):
    mesh = bpy.data.meshes.new("StarMesh")
    obj = bpy.data.objects.new("StarObj", mesh)
    bpy.context.collection.objects.link(obj)

    verts = []
    for z in [-depth/2.0 + z_pos, depth/2.0 + z_pos]:
        for i in range(10):
            ang = i * (math.pi / 5.0) - math.pi / 2.0
            r = r_out if i % 2 == 0 else r_in
            verts.append((math.cos(ang)*r, math.sin(ang)*r, z))

    verts.append((0, 0, -depth/2.0 + z_pos))
    verts.append((0, 0, depth/2.0 + z_pos))

    faces = []
    for i in range(10):
        faces.append((20, (i+1)%10, i))
    for i in range(10):
        faces.append((21, 10 + i, 10 + (i+1)%10))
    for i in range(10):
        next_i = (i+1)%10
        faces.append((i, next_i, 10 + next_i, 10 + i))

    mesh.from_pydata(verts, [], faces)
    mesh.update()
    return obj

def create_wavy_ribbon(name, y_base, amp, freq, phase, width_y=0.34, height_z=0.08, z_base=0.10, x_min=-1.32, x_max=1.32, steps=36, taper=True):
    """Generates a continuous smooth sinusoidal wavy ribbon of clay across the tile."""
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    verts = []
    for i in range(steps + 1):
        t = i / float(steps)
        x = x_min + t * (x_max - x_min)
        y_center = y_base + amp * math.sin(x * freq + phase)
        dy = amp * freq * math.cos(x * freq + phase)
        length = math.hypot(1.0, dy)
        nx = -dy / length
        ny = 1.0 / length

        # Smooth taper envelope at ends so ribbon stays neatly inside tile
        env = min(1.0, math.sin(t * math.pi) * 1.8) if taper else 1.0
        w_cur = width_y * env
        h_cur = height_z * max(0.4, env)

        half_w = w_cur * 0.5
        z_top = z_base + h_cur * 0.5
        z_bot = z_base - h_cur * 0.5

        # Cross section vertices
        lx = x + nx * half_w
        ly = y_center + ny * half_w
        rx = x - nx * half_w
        ry = y_center - ny * half_w

        verts.append((lx, ly, z_bot))  # 0: bot-left
        verts.append((lx, ly, z_top))  # 1: top-left
        verts.append((rx, ry, z_top))  # 2: top-right
        verts.append((rx, ry, z_bot))  # 3: bot-right

    faces = []
    for i in range(steps):
        v0 = i * 4
        v1 = (i + 1) * 4
        faces.append((v0 + 0, v1 + 0, v1 + 1, v0 + 1))  # Left side
        faces.append((v0 + 1, v1 + 1, v1 + 2, v0 + 2))  # Top surface
        faces.append((v0 + 2, v1 + 2, v1 + 3, v0 + 3))  # Right side
        faces.append((v0 + 3, v1 + 3, v1 + 0, v0 + 0))  # Bottom surface

    # End caps
    faces.append((0, 3, 2, 1))
    last_v = steps * 4
    faces.append((last_v + 1, last_v + 2, last_v + 3, last_v + 0))

    mesh.from_pydata(verts, [], faces)
    mesh.update()

    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_smooth()
    # Apply light subdivision for organic clay smoothness
    sub = obj.modifiers.new(name="Subsurf", type='SUBSURF')
    sub.levels = 1
    sub.render_levels = 1

    return obj

def create_lily_pad(name, radius=0.44, depth=0.05, notch_angle=math.radians(35), z_pos=0.14, steps=28):
    """Creates a circular clay lily pad with an authentic V-cut notch and gentle dished curvature."""
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    verts = []
    z_bot = z_pos - depth * 0.5
    z_top = z_pos + depth * 0.5
    # Center vertices slightly lower for gentle cupping
    verts.append((0.0, 0.0, z_bot - 0.01))  # 0: center bottom
    verts.append((0.0, 0.0, z_top - 0.01))  # 1: center top

    start_ang = notch_angle * 0.5
    end_ang = 2.0 * math.pi - notch_angle * 0.5
    for i in range(steps + 1):
        ang = start_ang + (i / float(steps)) * (end_ang - start_ang)
        x = math.cos(ang) * radius
        y = math.sin(ang) * radius
        verts.append((x, y, z_bot))  # 2 + i*2 + 0
        verts.append((x, y, z_top))  # 2 + i*2 + 1

    faces = []
    for i in range(steps):
        b0 = 2 + i * 2
        t0 = b0 + 1
        b1 = 2 + (i + 1) * 2
        t1 = b1 + 1
        faces.append((1, t0, t1))          # Top fan
        faces.append((0, b1, b0))          # Bottom fan
        faces.append((b0, b1, t1, t0))      # Outer rim

    # Notch edge walls
    first_b = 2
    first_t = 3
    last_b = 2 + steps * 2
    last_t = last_b + 1
    faces.append((0, 1, first_t, first_b))  # Start notch wall
    faces.append((0, last_b, last_t, 1))    # End notch wall

    mesh.from_pydata(verts, [], faces)
    mesh.update()

    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_smooth()
    sub = obj.modifiers.new(name="Subsurf", type='SUBSURF')
    sub.levels = 1
    sub.render_levels = 1

    return obj

# ==================== 1. SOKPOP TANKS ====================

def build_sokpop_tank(name_prefix, col_body, col_turret, col_trim,
                      barrel_count=1, barrel_len=0.95, barrel_thick=0.19,
                      is_heavy=False, is_plasma=False, frame=0):
    objs = []
    mat_body = create_clay_mat(f"{name_prefix}_b", col_body)
    mat_turret = create_clay_mat(f"{name_prefix}_t", col_turret)
    mat_track = create_clay_mat(f"{name_prefix}_tr", (0.32, 0.30, 0.36, 1.0), roughness=0.85)
    mat_trim = create_clay_mat(f"{name_prefix}_tm", col_trim)
    mat_eyes = create_clay_mat(f"{name_prefix}_ey", (0.15, 0.15, 0.2, 1.0), roughness=0.3)
    mat_bore = create_clay_mat(f"{name_prefix}_bore", (0.10, 0.10, 0.14, 1.0), roughness=0.9)
    mat_glow = create_clay_mat(f"{name_prefix}_gl", (0.35, 0.9, 1.0, 1.0), emission=(0.35, 0.9, 1.0, 1.0), emission_str=3.0)

    w = 1.45 if is_heavy else 1.3
    l = 1.55 if is_heavy else 1.4
    tw = 0.38 if is_heavy else 0.34
    tx = w * 0.5 + tw * 0.5 - 0.04
    tl = l * 1.1

    # 1. Main Hull with subtle chassis suspension bob
    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.012
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, bob_z))
    hull = bpy.context.active_object
    hull.scale = (w, l, 0.56)
    hull.data.materials.append(mat_body)
    apply_uniform_clay_bevel(hull, width=0.18, segments=4)
    objs.append(hull)

    # 2. Nose Wedge & Fender
    bpy.ops.mesh.primitive_cylinder_add(radius=w*0.42, depth=0.48, vertices=16, location=(0, l*0.42, 0.04 + bob_z))
    nose = bpy.context.active_object
    nose.rotation_euler = (0, math.radians(90), 0)
    nose.data.materials.append(mat_trim)
    apply_uniform_clay_bevel(nose, width=0.1, segments=3)
    objs.append(nose)

    # 3. Headlights
    for hx in [-w*0.28, w*0.28]:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.11, location=(hx, l*0.5, 0.12 + bob_z))
        hl = bpy.context.active_object
        hl.data.materials.append(mat_eyes)
        bpy.ops.object.shade_smooth()
        objs.append(hl)

    # 4. Tracks & Wheels
    for side, x_pos in [('L', -tx), ('R', tx)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos, 0, 0.02))
        tr = bpy.context.active_object
        tr.scale = (tw, tl, 0.6)
        tr.data.materials.append(mat_track)
        apply_uniform_clay_bevel(tr, width=0.16, segments=4)
        objs.append(tr)

        # 3 Hubcap Roadwheels with rotating rim studs
        wheel_rot = (frame / 6.0) * (2.0 * math.pi)
        for wy in [-0.45, 0.0, 0.45]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.24, depth=tw*1.08, vertices=16, location=(x_pos, wy, 0))
            wh = bpy.context.active_object
            wh.rotation_euler = (0, math.radians(90), 0)
            wh.data.materials.append(mat_trim)
            apply_uniform_clay_bevel(wh, width=0.08, segments=3)
            objs.append(wh)

            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.08, location=(x_pos + (0.08 if x_pos > 0 else -0.08), wy, 0))
            hub = bpy.context.active_object
            hub.data.materials.append(mat_body)
            bpy.ops.object.shade_smooth()
            objs.append(hub)

            # 3 Rotating Wheel Bolts/Studs per wheel
            for b_i in range(3):
                b_ang = wheel_rot + b_i * (2.0 * math.pi / 3.0)
                b_y = wy + math.sin(b_ang) * 0.14
                b_z = math.cos(b_ang) * 0.14
                b_x = x_pos + (0.09 if x_pos > 0 else -0.09)
                bpy.ops.mesh.primitive_uv_sphere_add(radius=0.032, location=(b_x, b_y, b_z))
                w_bolt = bpy.context.active_object
                w_bolt.data.materials.append(mat_trim)
                bpy.ops.object.shade_smooth()
                objs.append(w_bolt)

        # 6-Frame Continuous Tread Teeth animation offset
        num_treads = 6
        tread_spacing = (tl * 0.84) / float(num_treads)
        offset = (frame / 6.0) * tread_spacing
        for i in range(num_treads):
            y_pos = -tl*0.42 + (i / float(num_treads - 1)) * (tl * 0.84) + offset
            if y_pos > tl * 0.46: y_pos -= tl * 0.88
            bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=tw*1.05, vertices=12, location=(x_pos, y_pos, 0.32))
            tread = bpy.context.active_object
            tread.rotation_euler = (0, math.radians(90), 0)
            tread.data.materials.append(mat_body)
            apply_uniform_clay_bevel(tread, width=0.04, segments=2)
            objs.append(tread)

    # 5. Turret Dome
    tsize = 0.92 if is_heavy else 0.82
    bpy.ops.mesh.primitive_uv_sphere_add(radius=tsize*0.58, location=(0, -0.06, 0.52 + bob_z))
    turret = bpy.context.active_object
    turret.scale = (1.0, 1.0, 0.75)
    turret.data.materials.append(mat_turret)
    bpy.ops.object.shade_smooth()
    objs.append(turret)

    # 6. Hatch & Periscope
    bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=0.15, vertices=16, location=(0, -0.16, 0.82))
    hatch = bpy.context.active_object
    hatch.data.materials.append(mat_trim)
    apply_uniform_clay_bevel(hatch, width=0.08, segments=3)
    objs.append(hatch)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.22, 0.06, 0.80))
    peri = bpy.context.active_object
    peri.scale = (0.16, 0.14, 0.16)
    peri.data.materials.append(mat_trim)
    apply_uniform_clay_bevel(peri, width=0.04, segments=2)
    objs.append(peri)

    # 7. Cannons & Hollow Muzzle Bores
    if barrel_count == 1:
        bpy.ops.mesh.primitive_cylinder_add(radius=barrel_thick, depth=barrel_len, vertices=16, location=(0, 0.32 + barrel_len/2.0, 0.52))
        barrel = bpy.context.active_object
        barrel.rotation_euler = (math.radians(90), 0, 0)
        barrel.data.materials.append(mat_turret)
        apply_uniform_clay_bevel(barrel, width=0.06, segments=3)
        objs.append(barrel)

        bpy.ops.mesh.primitive_torus_add(major_radius=barrel_thick*1.35, minor_radius=0.08, location=(0, 0.32 + barrel_len, 0.52))
        muzzle = bpy.context.active_object
        muzzle.rotation_euler = (math.radians(90), 0, 0)
        muzzle.data.materials.append(mat_trim)
        bpy.ops.object.shade_smooth()
        objs.append(muzzle)

        bpy.ops.mesh.primitive_cylinder_add(radius=barrel_thick*0.65, depth=0.12, vertices=12, location=(0, 0.32 + barrel_len + 0.02, 0.52))
        bore = bpy.context.active_object
        bore.rotation_euler = (math.radians(90), 0, 0)
        bore.data.materials.append(mat_bore)
        objs.append(bore)

        if is_plasma:
            for py in [0.75, 1.15]:
                bpy.ops.mesh.primitive_torus_add(major_radius=barrel_thick*1.4, minor_radius=0.05, location=(0, py, 0.52))
                ring = bpy.context.active_object
                ring.rotation_euler = (math.radians(90), 0, 0)
                ring.data.materials.append(mat_glow)
                bpy.ops.object.shade_smooth()
                objs.append(ring)

    elif barrel_count == 2:
        for bx in [-0.24, 0.24]:
            bpy.ops.mesh.primitive_cylinder_add(radius=barrel_thick*0.85, depth=barrel_len, vertices=16, location=(bx, 0.32 + barrel_len/2.0, 0.52))
            barrel = bpy.context.active_object
            barrel.rotation_euler = (math.radians(90), 0, 0)
            barrel.data.materials.append(mat_turret)
            apply_uniform_clay_bevel(barrel, width=0.05, segments=3)
            objs.append(barrel)

            bpy.ops.mesh.primitive_torus_add(major_radius=barrel_thick*1.15, minor_radius=0.06, location=(bx, 0.32 + barrel_len, 0.52))
            muzzle = bpy.context.active_object
            muzzle.rotation_euler = (math.radians(90), 0, 0)
            muzzle.data.materials.append(mat_trim)
            bpy.ops.object.shade_smooth()
            objs.append(muzzle)

            bpy.ops.mesh.primitive_cylinder_add(radius=barrel_thick*0.55, depth=0.10, vertices=12, location=(bx, 0.32 + barrel_len + 0.02, 0.52))
            bore = bpy.context.active_object
            bore.rotation_euler = (math.radians(90), 0, 0)
            bore.data.materials.append(mat_bore)
            objs.append(bore)

    return objs

# ==================== 2. SOKPOP TILES ====================

def build_sokpop_brick():
    objs = []
    mat_clay = create_clay_mat("m_ub_c", (0.92, 0.48, 0.28, 1.0))
    mat_cream = create_clay_mat("m_ub_m", (0.94, 0.90, 0.82, 1.0))

    # 1. Full-Bleed Mortar Base Plate (3.34 units -> 0px gap between adjacent tiles)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.1))
    base = bpy.context.active_object
    base.scale = (TILE_PLATE_BLEED, TILE_PLATE_BLEED, 0.20)
    base.data.materials.append(mat_cream)
    apply_uniform_clay_bevel(base, width=0.08, segments=3, jitter=0.0)
    objs.append(base)

    # 2. 砖块排布 —— 必须*严格按画幅周期*对齐, 否则拼缝处会多出一道粗砖缝。
    #
    # 旧排布是手写的近似值 (y=±1.22/±0.41, x=±0.84/±1.26, 砖长 1.54/0.70),
    # 每一处都差一点点, 累计效果是:
    #   竖直: 砖高 0.62, 内部砖缝 0.19, 但顶边只剩 0.12、底边也 0.12 ——
    #         上下拼起来是 0.24 的缝, 比内部粗 26%, 于是每 48px 出现一道
    #         明显的横向暗带 (实测上下边色差 33.08)。
    #   水平: 内部砖缝 0.14, 而左右边各只剩 0.04, 拼起来 0.08, 比内部*细*一半。
    #
    # 现在全部由周期推导。画幅宽 P=3.30 (相机 ortho), 半宽 H=1.65:
    #   竖直 4 行 -> 行距 P/4 = 0.825, 砖高 0.62 => 砖缝恒为 0.205, 含跨缝处;
    #   水平砖距 P/2 = 1.65, 砖长 1.65-0.14 = 1.51 => 砖缝恒为 0.14。
    # 奇数行的砖心落在 0 和 ±H: 落在 ±H 的那块正好*骑在拼缝上*, 左右各画半块,
    # 拼起来就是一整块跨缝的砖 —— 这才是真正的顺砌 (running bond), 而不是
    # 每块瓦片各自凑一个近似的砖墙。
    P = ORTHO_SCALE_DEFAULT
    H = P * 0.5
    MORTAR_X = 0.14
    BRICK_LEN = P * 0.5 - MORTAR_X     # 1.51
    BRICK_H = 0.62
    row_pitch = P / 4.0                # 0.825

    base_centers = []
    for r_idx in range(4):
        y = -H + (r_idx + 0.5) * row_pitch
        if r_idx % 2 == 0:
            xs = [-P * 0.25, P * 0.25]             # ±0.825
        else:
            xs = [0.0, -H, H]                      # 中间一块 + 骑缝的那块
        for x in xs:
            base_centers.append((x, y))

    # 3. 把邻居瓦片的砖也摆出来 —— 这才是上下拼缝那道亮暗突变的真正原因。
    #
    # 砖高出砖缝 0.26, 太阳仰角 35°, 所以每块砖投出 0.26/tan(35°) = 0.371 长的
    # 影子, 比 0.205 的砖缝还长 —— 一块砖的影子足以盖满旁边整条砖缝。
    # 瓦片内部没问题 (每条砖缝两侧都有砖), 但画幅边上就不行了: 本该把下边缘
    # 砖缝压暗的那块砖属于*邻居瓦片*, 而渲染时场景里根本没有它。于是同一条
    # 砖缝, 上边缘渲成暗的、下边缘渲成亮的, 拼起来就是一道 36 的突变
    # (比瓦片内部最大的梯度 33 还大, 也就是比砖块自己的边缘还扎眼)。
    #
    # 解法是把这块瓦片当作*无限砖墙的一部分*来渲: 周围补一圈周期副本, 只留
    # 影子够得着画幅的那些 (阈值 H+0.9 已远大于 0.371 的影长)。
    # 这对任何"有高度差 + 定向光"的满幅瓦片都成立, 不止砖块。
    # 必须去重: 奇数行的砖心里有 -H 和 +H 两块, 而 -H 平移 +P 正好落在 +H 上。
    # 不去重就会有两块完全重合的立方体, Cycles 下 z-fighting, 渲出来是一片
    # 规律分布的深褐色砖 —— 第一次改完铺开一看就是这个症状。
    reach = H + 0.9
    seen = set()
    all_centers = []
    for dx in (-P, 0.0, P):
        for dy in (-P, 0.0, P):
            for (x, y) in base_centers:
                nx, ny = x + dx, y + dy
                if abs(nx) > reach or abs(ny) > reach:
                    continue
                key = (round(nx, 3), round(ny, 3))
                if key in seen:
                    continue
                seen.add(key)
                all_centers.append((nx, ny))

    for (x, y) in all_centers:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, y, 0.12))
        b = bpy.context.active_object
        b.scale = (BRICK_LEN, BRICK_H, 0.28)
        b.data.materials.append(mat_clay)
        # jitter 会破坏周期性 —— 骑缝那块砖的左右两半必须严丝合缝对上,
        # 顶点抖动是随机的, 一抖两边就错开, 拼缝处露出锯齿。
        apply_uniform_clay_bevel(b, width=0.08, segments=3, jitter=0.0)
        objs.append(b)
    return objs

def build_sokpop_steel():
    """不可摧毁的钢墙。

    两处改动都不是审美偏好, 是有依据的:

    1. **中央那块金盘去掉了。** 金/黄在本项目里是*敌方专用词汇* —— enemy_power /
       enemy_armor / enemy_basic 的描边都是金色 (见 ENEMY_PALETTES 的注释)。
       而这块瓦片原本顶着一个半径 0.75 的大金盘, 是全游戏面积最大的金色表面:
       地形穿着敌人的衣服。量化上它也确实过头 —— "中心区域相对整块的平均色偏"
       高达 51, 其余瓦片都在 1~14 之间, 铺开后整片钢墙读起来是一张波尔卡圆点
       桌布, 不是钢。现在换成压暗的钢制凸台, 靠明暗而不是靠色相做出中心。

    2. **铆钉挪到画幅四角和四边中点上。** 原来在 ±1.25, 距边 0.4 —— 铺开后
       相邻四块瓦片的四颗铆钉挤成一簇, 于是网格顶点上出现一团四点花纹, 反而
       把瓦片边界标了出来。放到 ±H 之后, 四块瓦片各出四分之一颗, 正好拼成
       *一颗*铆钉钉在网格顶点上, 读起来就是一整片连续的铆接钢板。
       (和 build_sokpop_trees 里边界树冠是同一个思路。)
    """
    objs = []
    P = ORTHO_SCALE_DEFAULT
    H = P * 0.5
    # 去掉金色之后必须重新拉开明度, 否则整块钢是一片没有层次的浅灰紫:
    #   - 48px 显示尺寸下, 只靠色相差的结构会全部糊掉;
    #   - 更要紧的是它会和 tile_ice (0.76,0.90,0.96 的浅冰蓝) 撞明度。原本那个
    #     大金盘顺带承担了"一眼区分钢和冰"的功能, 拿掉之后这件事得由明度接手。
    # 于是底板压暗、铆钉提亮: 暗底 + 亮铆钉读起来是"沉的铁", 冰是"透的亮",
    # 两者在明度上分开, 不再依赖色相。
    mat_plate = create_clay_mat("m_us_p", (0.70, 0.74, 0.83, 1.0))
    mat_rib = create_clay_mat("m_us_r", (0.60, 0.64, 0.75, 1.0))
    mat_boss = create_clay_mat("m_us_b", (0.44, 0.48, 0.60, 1.0), roughness=0.55)
    mat_rivet = create_clay_mat("m_us_v", (0.84, 0.87, 0.93, 1.0), roughness=0.40)

    # 1. Full-Bleed Steel Base Plate
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    plate = bpy.context.active_object
    plate.scale = (TILE_PLATE_BLEED, TILE_PLATE_BLEED, 0.35)
    plate.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(plate, width=0.12, segments=4, jitter=0.0)
    objs.append(plate)

    # 2. Reinforcement Cross Ribs
    for (sx, sy) in [(TILE_PLATE_BLEED, 0.46), (0.46, TILE_PLATE_BLEED)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.18))
        rib = bpy.context.active_object
        rib.scale = (sx, sy, 0.12)
        rib.data.materials.append(mat_rib)
        apply_uniform_clay_bevel(rib, width=0.06, segments=2, jitter=0.0)
        objs.append(rib)

    # 3. 中央钢制凸台 (原来是金盘)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.52, depth=0.20, vertices=8, location=(0, 0, 0.22))
    boss = bpy.context.active_object
    boss.data.materials.append(mat_boss)
    apply_uniform_clay_bevel(boss, width=0.06, segments=3, jitter=0.0)
    objs.append(boss)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.26, depth=0.12, vertices=8, location=(0, 0, 0.32))
    boss_top = bpy.context.active_object
    boss_top.data.materials.append(mat_rivet)
    apply_uniform_clay_bevel(boss_top, width=0.04, segments=2, jitter=0.0)
    objs.append(boss_top)

    # 4. 铆钉 —— 骑在画幅边线上, 拼起来才是一颗
    rivet_pos = [(-H, -H), (H, -H), (-H, H), (H, H),
                 (0.0, -H), (0.0, H), (-H, 0.0), (H, 0.0)]
    for (rx, ry) in rivet_pos:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.17, location=(rx, ry, 0.20))
        bolt = bpy.context.active_object
        bolt.data.materials.append(mat_rivet)
        bpy.ops.object.shade_smooth()
        objs.append(bolt)
    return objs

def build_sokpop_water(frame=0):
    objs = []
    mat_deep_water   = create_clay_mat("m_uw_dw", (0.12, 0.40, 0.68, 1.0), roughness=0.18, sss_weight=0.22)
    mat_mid_water    = create_clay_mat("m_uw_mw", (0.22, 0.64, 0.88, 1.0), roughness=0.16, sss_weight=0.24)
    mat_light_water  = create_clay_mat("m_uw_lw", (0.46, 0.88, 0.98, 1.0), roughness=0.14, sss_weight=0.26)
    mat_foam         = create_clay_mat("m_uw_fm", (0.96, 0.98, 1.0, 1.0), roughness=0.40)
    mat_bubble       = create_clay_mat("m_uw_bub", (0.88, 0.96, 1.0, 1.0), roughness=0.10)

    # 1. Full-Bleed Deep River Basin Base Block
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.06))
    base = bpy.context.active_object
    base.scale = (TILE_PLATE_BLEED, TILE_PLATE_BLEED, 0.32)
    base.data.materials.append(mat_deep_water)
    apply_uniform_clay_bevel(base, width=0.10, segments=3, jitter=0.0)
    objs.append(base)

    # 2. 5-Tier Seamless Multi-Tile River Wave Ribbons
    # Frequency is calibrated exactly to 2 full periods across ORTHO_SCALE_DEFAULT (3.30)
    frame_phase = frame * (2.0 * math.pi / 6.0)
    tile_period = ORTHO_SCALE_DEFAULT  # 3.30
    freq = (2.0 * math.pi * 2.0) / tile_period  # exactly 2 periods per tile width -> seamless across borders

    # 波形本身的周期 (一块瓦片里正好两个) —— 接缝的一切都要对齐到它
    wave_period = tile_period * 0.5    # 1.65
    half_frame = tile_period * 0.5     # 1.65, 相机实际看到的半宽

    # 缎带要生成到画幅*外*整整一个波长, 并且采样格必须能整除波长。
    #
    # 旧写法是 x∈[-1.67, 1.67] 配 steps=44: 一来缎带端面几乎就压在画幅边线上
    # (只出去 0.02), 二来 3.34/43 的采样间距根本不是波长的整数分之一, 于是
    # 分段折线逼近出的波形在左右两条边上*不一样* —— 正弦本身在 ±1.65 是严格
    # 对得上的 (相差 4π), 但折线逼近的误差对不上。实测左右边色差 24.87, 且
    # 集中在波形所在的那几行, 底板行几乎为零, 正是这个原因。
    #
    # 现在: 跨度 4 个波长, 96 段 -> 每段 = 波长/24, 折线逼近严格周期,
    # ±1.65 处必然一致。
    span_ext = half_frame + wave_period          # 3.30
    steps_ext = 96                               # 6.60 / 96 = 1.65/24

    half_span = span_ext

    wave_tiers = [
        # (name, y_base, amp, phase_offset, width_y, height_z, z_base)
        ("WaveRow0",  1.26, 0.15, 0.0,  0.54, 0.11, 0.08),
        ("WaveRow1",  0.63, 0.18, 1.3,  0.58, 0.13, 0.10),
        ("WaveRow2",  0.00, 0.20, 2.6,  0.60, 0.14, 0.11),
        ("WaveRow3", -0.63, 0.18, 3.9,  0.58, 0.13, 0.10),
        ("WaveRow4", -1.26, 0.15, 5.2,  0.54, 0.11, 0.08),
    ]

    for name, y_base, amp, row_phase, wy, hz, zb in wave_tiers:
        cur_phase = row_phase + frame_phase

        # Main wave body ribbon spanning full tile width without tapering
        wv = create_wavy_ribbon(f"{name}_Body", y_base, amp, freq, cur_phase,
                                width_y=wy, height_z=hz, z_base=zb,
                                x_min=-half_span, x_max=half_span, steps=steps_ext, taper=False)
        wv.data.materials.append(mat_mid_water)
        objs.append(wv)

        # Upper wave crest highlight ribbon
        wv_crest = create_wavy_ribbon(f"{name}_Crest", y_base, amp, freq, cur_phase,
                                      width_y=wy * 0.38, height_z=hz * 0.60, z_base=zb + hz * 0.32,
                                      x_min=-half_span, x_max=half_span, steps=steps_ext, taper=False)
        wv_crest.data.materials.append(mat_light_water)
        objs.append(wv_crest)

        # 浪尖白沫。峰值每 wave_period 出现一次, 所以按波长枚举, 而不是像旧写法
        # 那样只取两个峰再按 tile_period(3.30) 回绕 —— 回绕步长是波长的两倍,
        # 会漏掉一半的峰, 而且靠近边缘的峰被 |x|<=1.30 直接丢掉, 于是左边有沫、
        # 右边没有。这里画到画幅外一点, 让骑在拼缝上的白沫两边各露一半。
        x0 = (0.5 * math.pi - cur_phase) / freq
        k_lo = int(math.floor((-half_frame - 0.30 - x0) / wave_period))
        k_hi = int(math.ceil((half_frame + 0.30 - x0) / wave_period))
        for k in range(k_lo, k_hi + 1):
            peak_x = x0 + k * wave_period

            flen = 0.52
            if -(half_frame + 0.30) <= peak_x <= (half_frame + 0.30):
                fm = create_wavy_ribbon(f"{name}_Foam_{k}", y_base, amp, freq, cur_phase,
                                        width_y=0.065, height_z=0.04, z_base=zb + hz * 0.45,
                                        x_min=peak_x - flen * 0.5, x_max=peak_x + flen * 0.5, steps=16, taper=True)
                fm.data.materials.append(mat_foam)
                objs.append(fm)

                # Sparkling bubble droplets beside foam cap
                bx = peak_x + flen * 0.30
                by = y_base + amp * math.sin(bx * freq + cur_phase) + 0.04
                bpy.ops.mesh.primitive_uv_sphere_add(radius=0.045, location=(bx, by, zb + hz * 0.48))
                bub = bpy.context.active_object
                bub.data.materials.append(mat_bubble)
                bpy.ops.object.shade_smooth()
                objs.append(bub)

    return objs

def build_sokpop_trees():
    objs = []
    mat_matcha = create_clay_mat("m_ut_m", (0.34, 0.72, 0.30, 1.0))
    mat_lime = create_clay_mat("m_ut_l", (0.50, 0.82, 0.34, 1.0))
    mat_trunk = create_clay_mat("m_ut_tr", (0.45, 0.28, 0.18, 1.0))
    mat_berry = create_clay_mat("m_ut_b", (0.92, 0.30, 0.40, 1.0))

    # 1. Exposed Wooden Trunk/Stump Base
    for (tx, ty) in [(-0.65, -0.65), (0.65, 0.65)]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.32, depth=0.45, vertices=12, location=(tx, ty, 0.08))
        trunk = bpy.context.active_object
        trunk.data.materials.append(mat_trunk)
        apply_uniform_clay_bevel(trunk, width=0.06, segments=2)
        objs.append(trunk)

    # 2. Rich Layered Canopy Volumes spanning full footprint
    spheres = [
        # Base canopy layer (dark matcha)
        (-0.95, -0.95, 0.38, 0.88, mat_matcha), (0.95, -0.95, 0.38, 0.88, mat_matcha),
        (-0.95, 0.95, 0.38, 0.88, mat_matcha), (0.95, 0.95, 0.38, 0.88, mat_matcha),
        # Mid-tier lush foliage (vibrant lime)
        (-0.85, 0.0, 0.50, 0.85, mat_lime), (0.85, 0.0, 0.50, 0.85, mat_lime),
        (0.0, -0.85, 0.50, 0.85, mat_lime), (0.0, 0.85, 0.50, 0.85, mat_lime),
        # Crown summit dome
        (0.0, 0.0, 0.82, 1.15, mat_lime),
        (-0.25, 0.25, 1.12, 0.70, mat_matcha)
    ]

    # 3'. 边界树冠 —— 球心*落在画幅边线上*, 不是装饰而是补洞。
    #
    # 这块瓦片没有底板 (main.gd::_spawn_tile 把 trees 当独立 Sprite2D 画在
    # z_index=10, 底下没有地面), 所以树冠盖不到的地方直接漏背景。实测边缘有
    # 21% 的像素 alpha<250, 铺成 3x3 后内部有 160 个像素是全透明的 —— 在网格
    # 顶点上表现为一圈深色针孔。
    #
    # 缺口位置是算得出来的: 画幅半宽 = TILE_FULL_BLEED/2 = 1.67。
    #   角点 (1.67,1.67) 到最近的基础树冠 (0.95,0.95) 距离 sqrt(0.72^2*2)=1.018,
    #   而那个球半径只有 0.88 —— 差 0.14。
    #   边中段 (1.67,0.35): 到 (0.95,0.95) 是 0.937>0.88, 到 (0.85,0) 是
    #   0.892>0.85 —— 两个球之间本来就有条缝。
    # 与实测的缺口段完全吻合 (角落 ±1.50~±1.67, 边中段 ±0.27~±0.44)。
    #
    # 为什么球心放在边线上而不是把原有的球放大: 相邻两块瓦片拼接时, 各自的
    # 半个球正好凑成一整棵跨缝的树, 缝两侧的形体自然连续 —— 森林本来就该这样,
    # 而单纯放大树冠只会让每块瓦片各自变胖, 缝还在。
    # _HB 必须是*相机画幅*的半宽, 不是底板满幅尺寸的一半。
    # 原来写的是 TILE_FULL_BLEED/2 = 1.67, 但相机 ortho 只有 3.30, 半宽 1.65 ——
    # 差的这 0.02 单位 (约 1.5px) 会让边界树冠稍稍偏出画幅, 更要命的是它破坏了
    # 周期性: 按 3.30 平铺时, +1.67 的球对应到邻居那边是 -1.63, 和本块自己
    # -1.67 的球差 0.04, 拼缝处于是多出一道细微的重影。
    _P = ORTHO_SCALE_DEFAULT
    _HB = _P * 0.5
    # 边界环必须*连续*, 而且必须是画幅边线上的最高面。
    #
    # 原来只在 t=±0.35 和四角放球, 中间 x≈±1.03 那一段是空的 —— 那里露出来的
    # 是底层树冠 (±0.95, r0.88) 的侧面。而底层树冠不是周期排布的: 上边缘看到的
    # 是 (0.95,0.95) 那颗球的 +y 侧, 下边缘看到的是 (0.95,-0.95) 那颗球的 -y 侧,
    # 定向光下这两侧本来就不一样亮, 于是拼缝处出现一道明暗错位。实测上下拼接
    # 梯度 8.3 正是集中在 x≈±1.03 这两段 (其余列只有 2.4)。
    #
    # 补齐 t=±1.05 让环连续, 并把整个环抬到 z=0.42: 边线上的最高面因此全部由
    # 边界环承担, 而边界环是严格按画幅周期摆的 —— 上下两边看到的是*同一颗球*
    # 的两半 (本块的 +_HB 与 -_HB 互为周期副本), 明暗自然对得上。
    _RZ = 0.42
    for (bx, by) in [(-_HB, -_HB), (_HB, -_HB), (-_HB, _HB), (_HB, _HB)]:
        spheres.append((bx, by, _RZ, 0.64, mat_matcha))
    for t in (-1.05, -0.35, 0.35, 1.05):
        spheres += [(_HB, t, _RZ, 0.60, mat_matcha), (-_HB, t, _RZ, 0.60, mat_matcha),
                    (t, _HB, _RZ, 0.60, mat_matcha), (t, -_HB, _RZ, 0.60, mat_matcha)]

    # 和砖块同理: 把邻居瓦片的树冠也摆出来, 让画幅边缘的遮挡和投影连续。
    # 树冠是球, 高度差比砖块还大, 缺了邻居就等于边缘的树"半边悬空", 明暗对不上
    # (实测上下拼缝梯度 9.88, 而瓦片内部最大梯度只有 2.41 —— 树冠本身是平滑的,
    # 所以任何一点突变都格外显眼)。
    # 去重: 边界球按周期平移后会和本块已有的球重合, 重复几何没意义。
    # 剔除半径要按*影长*算, 不是按"看不看得见"。树冠顶到 z≈1.97, 太阳仰角 35°,
    # 影长 1.97/tan(35°) ≈ 2.81 —— 邻居那个大穹顶自己完全在画幅外, 它的影子却
    # 照样能斜着盖进来。先前按 _HB+1.0=2.65 剔除, 正好把这些穹顶副本剔掉了,
    # 于是上下拼缝只从 9.88 降到 8.31。放宽到覆盖影长即可。
    _reach = _HB + 2.9
    _seen = set()
    _emit = []
    for dx in (-_P, 0.0, _P):
        for dy in (-_P, 0.0, _P):
            for (x, y, z, r, m) in spheres:
                nx, ny = x + dx, y + dy
                if abs(nx) > _reach or abs(ny) > _reach:
                    continue
                key = (round(nx, 3), round(ny, 3), round(z, 3), round(r, 3))
                if key in _seen:
                    continue
                _seen.add(key)
                _emit.append((nx, ny, z, r, m))

    for x, y, z, r, m in _emit:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=(x, y, z))
        b = bpy.context.active_object
        b.data.materials.append(m)
        bpy.ops.object.shade_smooth()
        objs.append(b)

    # 3. Clustered Berry Bunches
    berry_clusters = [
        (-0.42, -0.32, 1.25), (-0.32, -0.42, 1.22),
        (0.52, 0.32, 1.18), (0.42, 0.45, 1.20),
        (0.12, -0.65, 1.12),
        (-0.22, 0.62, 1.28)
    ]
    for bx, by, bz in berry_clusters:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(bx, by, bz))
        berry = bpy.context.active_object
        berry.data.materials.append(mat_berry)
        bpy.ops.object.shade_smooth()
        objs.append(berry)

    return objs

def build_sokpop_ice():
    objs = []
    mat_sugar = create_clay_mat("m_ui_s", (0.76, 0.90, 0.96, 1.0), roughness=0.22, sss_weight=0.12)
    mat_fracture = create_clay_mat("m_ui_fr", (0.60, 0.78, 0.88, 1.0))
    mat_sparkle = create_clay_mat("m_ui_sp", (0.95, 0.98, 1.0, 1.0))

    # 1. Full-Bleed Main Ice Block
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    ice = bpy.context.active_object
    ice.scale = (TILE_FULL_BLEED, TILE_FULL_BLEED, 0.30)
    ice.data.materials.append(mat_sugar)
    apply_uniform_clay_bevel(ice, width=0.10, segments=3, jitter=0.0)
    objs.append(ice)

    # 2. Crystalline Fracture Veins
    fractures = [
        (-0.65, -0.55, 1.05, 28),
        (0.55, 0.62, 0.92, -35),
        (-0.35, 0.78, 0.75, 55),
        (0.70, -0.65, 0.65, -65)
    ]
    for (px, py, l, angle) in fractures:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(px, py, 0.16))
        s = bpy.context.active_object
        s.scale = (l, 0.08, 0.04)
        s.rotation_euler = (0, 0, math.radians(angle))
        s.data.materials.append(mat_fracture)
        apply_uniform_clay_bevel(s, width=0.02, segments=2, jitter=0.0)
        objs.append(s)

    # 3. Four-pointed Glint Sparkles
    for (gx, gy) in [(-0.35, 0.25), (0.50, -0.20)]:
        star = create_3d_star(r_out=0.32, r_in=0.12, depth=0.08, z_pos=0.18)
        star.location = (gx, gy, 0)
        star.data.materials.append(mat_sparkle)
        apply_uniform_clay_bevel(star, width=0.02, segments=2)
        objs.append(star)

    return objs

def build_sokpop_eagle(destroyed=False):
    objs = []
    mat_ped = create_clay_mat("m_ue_p", (0.85, 0.80, 0.74, 1.0) if not destroyed else (0.42, 0.40, 0.45, 1.0))
    mat_chick = create_clay_mat("m_ue_c", (0.98, 0.82, 0.22, 1.0))
    mat_beak = create_clay_mat("m_ue_b", (0.98, 0.52, 0.15, 1.0))
    mat_crown = create_clay_mat("m_ue_cr", (0.98, 0.76, 0.15, 1.0))
    mat_ruby = create_clay_mat("m_ue_rb", (0.92, 0.20, 0.30, 1.0))
    mat_blush = create_clay_mat("m_ue_bl", (0.98, 0.42, 0.52, 1.0))
    mat_eyes = create_clay_mat("m_ue_e", (0.15, 0.15, 0.2, 1.0), roughness=0.2)
    mat_sparkle = create_clay_mat("m_ue_sp", (1.0, 1.0, 1.0, 1.0), emission=(1.0, 1.0, 1.0, 1.0), emission_str=2.0)

    bpy.ops.mesh.primitive_cylinder_add(radius=1.35, depth=0.35, vertices=16, location=(0, 0, 0))
    ped = bpy.context.active_object
    ped.data.materials.append(mat_ped)
    apply_uniform_clay_bevel(ped, width=0.12, segments=3)
    objs.append(ped)

    if not destroyed:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.85, location=(0, 0.05, 0.65))
        body = bpy.context.active_object
        body.data.materials.append(mat_chick)
        bpy.ops.object.shade_smooth()
        objs.append(body)

        for sign in [-1, 1]:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.45, location=(sign * 0.75, 0.05, 0.65))
            w = bpy.context.active_object
            w.scale = (0.5, 1.0, 0.7)
            w.rotation_euler = (0, 0, math.radians(sign * -25))
            w.data.materials.append(mat_chick)
            bpy.ops.object.shade_smooth()
            objs.append(w)

        bpy.ops.mesh.primitive_cone_add(radius1=0.22, depth=0.35, location=(0, 0.85, 0.65))
        beak = bpy.context.active_object
        beak.rotation_euler = (math.radians(90), 0, 0)
        beak.data.materials.append(mat_beak)
        apply_uniform_clay_bevel(beak, width=0.06, segments=2)
        objs.append(beak)

        bpy.ops.mesh.primitive_cylinder_add(radius=0.32, depth=0.22, vertices=12, location=(0, 0.05, 1.42))
        crown = bpy.context.active_object
        crown.data.materials.append(mat_crown)
        apply_uniform_clay_bevel(crown, width=0.04, segments=2)
        objs.append(crown)

        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.08, location=(0, 0.32, 1.45))
        gem = bpy.context.active_object
        gem.data.materials.append(mat_ruby)
        bpy.ops.object.shade_smooth()
        objs.append(gem)

        for sx in [-0.28, 0.28]:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.14, location=(sx, 0.72, 0.82))
            eye = bpy.context.active_object
            eye.data.materials.append(mat_eyes)
            bpy.ops.object.shade_smooth()
            objs.append(eye)

            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.05, location=(sx + 0.04, 0.82, 0.88))
            sp = bpy.context.active_object
            sp.data.materials.append(mat_sparkle)
            bpy.ops.object.shade_smooth()
            objs.append(sp)

            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(sx * 1.35, 0.68, 0.62))
            bl = bpy.context.active_object
            bl.data.materials.append(mat_blush)
            bpy.ops.object.shade_smooth()
            objs.append(bl)
    else:
        for i, (rx, ry, rz, s) in enumerate([(-0.6, -0.3, 0.3, 0.5), (0.5, 0.3, 0.3, 0.55), (0, 0.1, 0.35, 0.65)]):
            bpy.ops.mesh.primitive_uv_sphere_add(radius=s*0.8, location=(rx, ry, rz))
            rub = bpy.context.active_object
            rub.data.materials.append(mat_ped)
            bpy.ops.object.shade_smooth()
            objs.append(rub)

        bpy.ops.mesh.primitive_cylinder_add(radius=0.28, depth=0.20, vertices=12, location=(0.4, -0.4, 0.25))
        fc = bpy.context.active_object
        fc.rotation_euler = (math.radians(35), math.radians(20), math.radians(-45))
        fc.data.materials.append(mat_crown)
        apply_uniform_clay_bevel(fc, width=0.04, segments=2)
        objs.append(fc)

    return objs

# ==================== 3. SOKPOP BUILDINGS ====================

def build_sokpop_turret_base():
    objs = []
    mat_b = create_clay_mat("m_ubld_tb", (0.35, 0.38, 0.45, 1.0))
    mat_plate = create_clay_mat("m_ubld_tp", (0.50, 0.55, 0.62, 1.0))
    mat_r = create_clay_mat("m_ubld_tr", (0.35, 0.85, 1.0, 1.0), emission=(0.35, 0.85, 1.0, 1.0), emission_str=2.0)
    mat_gold = create_clay_mat("m_ubld_tg_bolt", (0.95, 0.78, 0.22, 1.0))

    # 1. Octagonal Anchor Base Plate
    bpy.ops.mesh.primitive_cylinder_add(radius=1.22, depth=0.18, vertices=8, location=(0, 0, -0.04))
    b = bpy.context.active_object
    b.data.materials.append(mat_b)
    apply_uniform_clay_bevel(b, width=0.08, segments=3)
    objs.append(b)

    # 4 Corner Anchor Feet with Bolts
    for (fx, fy) in [(-0.95, -0.95), (0.95, -0.95), (-0.95, 0.95), (0.95, 0.95)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(fx, fy, 0.04))
        foot = bpy.context.active_object
        foot.scale = (0.36, 0.36, 0.14)
        foot.data.materials.append(mat_plate)
        apply_uniform_clay_bevel(foot, width=0.04, segments=2)
        objs.append(foot)

        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.07, location=(fx, fy, 0.12))
        bolt = bpy.context.active_object
        bolt.data.materials.append(mat_gold)
        bpy.ops.object.shade_smooth()
        objs.append(bolt)

    # 2. Turntable Ring & Glowing Track
    bpy.ops.mesh.primitive_cylinder_add(radius=0.98, depth=0.18, vertices=20, location=(0, 0, 0.08))
    ring_mount = bpy.context.active_object
    ring_mount.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(ring_mount, width=0.06, segments=3)
    objs.append(ring_mount)

    bpy.ops.mesh.primitive_torus_add(major_radius=0.88, minor_radius=0.07, location=(0, 0, 0.18))
    r = bpy.context.active_object
    r.data.materials.append(mat_r)
    bpy.ops.object.shade_smooth()
    objs.append(r)

    return objs

def build_sokpop_turret_gun():
    objs = []
    mat_g = create_clay_mat("m_ubld_tg", (0.32, 0.62, 0.92, 1.0))
    mat_mantlet = create_clay_mat("m_ubld_tmantlet", (0.26, 0.48, 0.75, 1.0))
    mat_m = create_clay_mat("m_ubld_tm", (0.98, 0.80, 0.22, 1.0))
    mat_bore = create_clay_mat("m_ubld_tbore", (0.10, 0.10, 0.14, 1.0))
    mat_optic = create_clay_mat("m_ubld_toptic", (0.98, 0.35, 0.45, 1.0), emission=(0.98, 0.35, 0.45, 1.0), emission_str=2.0)

    # 1. Main Dome (EXACT CENTERED PIVOT AT (0, 0, 0.2))
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.68, location=(0, 0, 0.2))
    d = bpy.context.active_object
    d.scale = (1.0, 1.0, 0.85)
    d.data.materials.append(mat_g)
    bpy.ops.object.shade_smooth()
    objs.append(d)

    # 2. Top Hatch
    bpy.ops.mesh.primitive_cylinder_add(radius=0.28, depth=0.12, vertices=16, location=(0, -0.10, 0.74))
    hatch = bpy.context.active_object
    hatch.data.materials.append(mat_m)
    apply_uniform_clay_bevel(hatch, width=0.04, segments=2)
    objs.append(hatch)

    # 3. Optical Targeting Sensor / Eye
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(0, 0.50, 0.55))
    eye = bpy.context.active_object
    eye.data.materials.append(mat_optic)
    bpy.ops.object.shade_smooth()
    objs.append(eye)

    # 4. Gun Mantlet (Protective recoil collar block spanning the front)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.45, 0.20))
    mantlet = bpy.context.active_object
    mantlet.scale = (0.72, 0.32, 0.36)
    mantlet.data.materials.append(mat_mantlet)
    apply_uniform_clay_bevel(mantlet, width=0.06, segments=3)
    objs.append(mantlet)

    # 5. Dual Cannons emerging cleanly from Mantlet
    for bx in [-0.22, 0.22]:
        # Barrel
        bpy.ops.mesh.primitive_cylinder_add(radius=0.10, depth=1.05, vertices=16, location=(bx, 0.60, 0.20))
        barrel = bpy.context.active_object
        barrel.rotation_euler = (math.radians(90), 0, 0)
        barrel.data.materials.append(mat_g)
        apply_uniform_clay_bevel(barrel, width=0.04, segments=2)
        objs.append(barrel)

        # Recoil Collar Ring at the base of the barrel
        bpy.ops.mesh.primitive_torus_add(major_radius=0.13, minor_radius=0.04, location=(bx, 0.52, 0.20))
        rc = bpy.context.active_object
        rc.rotation_euler = (math.radians(90), 0, 0)
        rc.data.materials.append(mat_m)
        bpy.ops.object.shade_smooth()
        objs.append(rc)

        # Muzzle Brake
        bpy.ops.mesh.primitive_torus_add(major_radius=0.14, minor_radius=0.06, location=(bx, 1.12, 0.20))
        muzzle = bpy.context.active_object
        muzzle.rotation_euler = (math.radians(90), 0, 0)
        muzzle.data.materials.append(mat_m)
        bpy.ops.object.shade_smooth()
        objs.append(muzzle)

        # Bore Hole
        bpy.ops.mesh.primitive_cylinder_add(radius=0.07, depth=0.10, vertices=12, location=(bx, 1.14, 0.20))
        bore = bpy.context.active_object
        bore.rotation_euler = (math.radians(90), 0, 0)
        bore.data.materials.append(mat_bore)
        objs.append(bore)

    return objs

def build_sokpop_fortified_wall():
    objs = []
    mat_wall = create_clay_mat("m_ubld_w", (0.36, 0.42, 0.50, 1.0))
    mat_steel = create_clay_mat("m_ubld_ws", (0.75, 0.80, 0.88, 1.0))
    mat_gold = create_clay_mat("m_ubld_wg", (0.95, 0.78, 0.22, 1.0))
    mat_core = create_clay_mat("m_ubld_wc", (0.98, 0.35, 0.48, 1.0), emission=(0.98, 0.35, 0.48, 1.0), emission_str=2.5)

    # 1. Main Base Block
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    w = bpy.context.active_object
    w.scale = (2.85, 2.85, 0.38)
    w.data.materials.append(mat_wall)
    apply_uniform_clay_bevel(w, width=0.20, segments=4)
    objs.append(w)

    # 2. Heavy Corner Steel Brackets (4 corners)
    bracket_pos = [(-1.15, -1.15), (1.15, -1.15), (-1.15, 1.15), (1.15, 1.15)]
    for (bx, by) in bracket_pos:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(bx, by, 0.16))
        brk = bpy.context.active_object
        brk.scale = (0.65, 0.65, 0.14)
        brk.data.materials.append(mat_steel)
        apply_uniform_clay_bevel(brk, width=0.08, segments=3)
        objs.append(brk)

        # Rivet on each bracket
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.10, location=(bx, by, 0.24))
        bolt = bpy.context.active_object
        bolt.data.materials.append(mat_gold)
        bpy.ops.object.shade_smooth()
        objs.append(bolt)

    # 3. Cross-brace Ribs (Diagonal steel plates)
    for (sx, sy) in [(2.2, 0.32), (0.32, 2.2)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.14))
        rib = bpy.context.active_object
        rib.scale = (sx, sy, 0.12)
        rib.data.materials.append(mat_steel)
        apply_uniform_clay_bevel(rib, width=0.05, segments=2)
        objs.append(rib)

    # 4. Central Shield Medallion Bezel
    bpy.ops.mesh.primitive_cylinder_add(radius=0.85, depth=0.18, vertices=16, location=(0, 0, 0.18))
    bezel = bpy.context.active_object
    bezel.data.materials.append(mat_steel)
    apply_uniform_clay_bevel(bezel, width=0.06, segments=3)
    objs.append(bezel)

    # 5. Glowing Power Crystal Core (Octagonal / Shield core)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.60, depth=0.14, vertices=8, location=(0, 0, 0.24))
    core = bpy.context.active_object
    core.data.materials.append(mat_core)
    apply_uniform_clay_bevel(core, width=0.05, segments=2)
    objs.append(core)

    return objs

def build_sokpop_landmine():
    objs = []
    mat_base = create_clay_mat("m_ubld_mb", (0.30, 0.34, 0.40, 1.0))
    mat_metal = create_clay_mat("m_ubld_mm", (0.55, 0.60, 0.66, 1.0))
    mat_hazard = create_clay_mat("m_ubld_mh", (0.98, 0.78, 0.18, 1.0))
    mat_core = create_clay_mat("m_ubld_mc", (0.95, 0.28, 0.35, 1.0), emission=(0.95, 0.28, 0.35, 1.0), emission_str=2.5)

    # 1. Stepped Base Disc
    bpy.ops.mesh.primitive_cylinder_add(radius=1.15, depth=0.18, vertices=20, location=(0, 0, 0))
    base = bpy.context.active_object
    base.data.materials.append(mat_base)
    apply_uniform_clay_bevel(base, width=0.08, segments=3)
    objs.append(base)

    # 2. Upper Armored Hull Disc
    bpy.ops.mesh.primitive_cylinder_add(radius=0.90, depth=0.16, vertices=16, location=(0, 0, 0.10))
    hull = bpy.context.active_object
    hull.data.materials.append(mat_metal)
    apply_uniform_clay_bevel(hull, width=0.06, segments=3)
    objs.append(hull)

    # 3. Hazard Warning Ring
    bpy.ops.mesh.primitive_torus_add(major_radius=0.76, minor_radius=0.06, location=(0, 0, 0.18))
    hr = bpy.context.active_object
    hr.data.materials.append(mat_hazard)
    bpy.ops.object.shade_smooth()
    objs.append(hr)

    # 4. 4 Radial Pressure Trigger Prongs / Studs
    for i in range(4):
        ang = i * (math.pi / 2.0) + math.pi / 4.0
        bx = math.cos(ang) * 0.76
        by = math.sin(ang) * 0.76
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(bx, by, 0.19))
        stud = bpy.context.active_object
        stud.scale = (0.22, 0.22, 0.10)
        stud.rotation_euler = (0, 0, ang)
        stud.data.materials.append(mat_hazard)
        apply_uniform_clay_bevel(stud, width=0.03, segments=2)
        objs.append(stud)

    # 5. Core Collar & Glowing Detonator Core
    bpy.ops.mesh.primitive_cylinder_add(radius=0.45, depth=0.14, vertices=16, location=(0, 0, 0.19))
    col = bpy.context.active_object
    col.data.materials.append(mat_base)
    apply_uniform_clay_bevel(col, width=0.04, segments=2)
    objs.append(col)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.34, location=(0, 0, 0.22))
    c = bpy.context.active_object
    c.scale = (1.0, 1.0, 0.7)
    c.data.materials.append(mat_core)
    bpy.ops.object.shade_smooth()
    objs.append(c)

    return objs

def build_sokpop_repair_station():
    objs = []
    mat_pad = create_clay_mat("m_ubld_rp", (0.88, 0.90, 0.94, 1.0))
    mat_steel = create_clay_mat("m_ubld_rs", (0.35, 0.40, 0.48, 1.0))
    mat_cross_rim = create_clay_mat("m_ubld_rcr", (0.25, 0.65, 0.40, 1.0))
    mat_cross = create_clay_mat("m_ubld_rc", (0.28, 0.88, 0.50, 1.0), emission=(0.28, 0.88, 0.50, 1.0), emission_str=2.5)
    mat_ring = create_clay_mat("m_ubld_rr", (0.30, 0.82, 0.95, 1.0), emission=(0.30, 0.82, 0.95, 1.0), emission_str=2.0)
    mat_gold = create_clay_mat("m_ubld_rg", (0.98, 0.80, 0.22, 1.0))

    # 1. Main Octagonal/Circular Pad Base
    bpy.ops.mesh.primitive_cylinder_add(radius=1.25, depth=0.22, vertices=24, location=(0, 0, 0))
    p = bpy.context.active_object
    p.data.materials.append(mat_pad)
    apply_uniform_clay_bevel(p, width=0.08, segments=3)
    objs.append(p)

    # 2. Outer Concentric Energy Runway Ring
    bpy.ops.mesh.primitive_torus_add(major_radius=1.05, minor_radius=0.06, location=(0, 0, 0.10))
    r = bpy.context.active_object
    r.data.materials.append(mat_ring)
    bpy.ops.object.shade_smooth()
    objs.append(r)

    # 3. Medical Cross Recessed Bezel
    for (sx, sy) in [(1.35, 0.52), (0.52, 1.35)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.10))
        c_rim = bpy.context.active_object
        c_rim.scale = (sx, sy, 0.12)
        c_rim.data.materials.append(mat_cross_rim)
        apply_uniform_clay_bevel(c_rim, width=0.04, segments=2)
        objs.append(c_rim)

    # 4. Glowing Medical Cross Center
    for (sx, sy) in [(1.15, 0.38), (0.38, 1.15)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.14))
        c = bpy.context.active_object
        c.scale = (sx, sy, 0.12)
        c.data.materials.append(mat_cross)
        apply_uniform_clay_bevel(c, width=0.04, segments=2)
        objs.append(c)

    # 5. 4 Corner Nanite Emitter Pylons
    for (px, py) in [(-0.85, -0.85), (0.85, -0.85), (-0.85, 0.85), (0.85, 0.85)]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.12, depth=0.30, vertices=12, location=(px, py, 0.15))
        pyl = bpy.context.active_object
        pyl.data.materials.append(mat_steel)
        apply_uniform_clay_bevel(pyl, width=0.03, segments=2)
        objs.append(pyl)

        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.09, location=(px, py, 0.32))
        tip = bpy.context.active_object
        tip.data.materials.append(mat_cross)
        bpy.ops.object.shade_smooth()
        objs.append(tip)

    return objs

# ==================== 4. SOKPOP MAP TOKENS ====================

def build_sokpop_map_node(type_name):
    objs = []
    mat_base = create_clay_mat("m_um_base", (0.86, 0.80, 0.72, 1.0))
    mat_rim = create_clay_mat("m_um_rim", (0.75, 0.68, 0.58, 1.0))

    # Base Disc Pedestal with Beveled Rim
    bpy.ops.mesh.primitive_cylinder_add(radius=1.25, depth=0.28, vertices=24, location=(0, 0, 0))
    disc = bpy.context.active_object
    disc.data.materials.append(mat_base)
    apply_uniform_clay_bevel(disc, width=0.10, segments=3)
    objs.append(disc)

    bpy.ops.mesh.primitive_torus_add(major_radius=1.12, minor_radius=0.06, location=(0, 0, 0.12))
    rim = bpy.context.active_object
    rim.data.materials.append(mat_rim)
    bpy.ops.object.shade_smooth()
    objs.append(rim)

    if type_name == "battle":
        mat_blade = create_clay_mat("m_um_blade", (0.85, 0.88, 0.94, 1.0))
        mat_guard = create_clay_mat("m_um_guard", (0.95, 0.75, 0.20, 1.0))
        mat_grip = create_clay_mat("m_um_grip", (0.65, 0.25, 0.22, 1.0))
        mat_pommel = create_clay_mat("m_um_pommel", (0.95, 0.75, 0.20, 1.0))

        # Crossed Dual Broadswords
        for ang in [-38, 38]:
            rad = math.radians(ang)
            # Blade
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.28, 0.26))
            blade = bpy.context.active_object
            blade.scale = (0.22, 1.15, 0.10)
            blade.rotation_euler = (0, 0, rad)
            blade.data.materials.append(mat_blade)
            apply_uniform_clay_bevel(blade, width=0.04, segments=2)
            objs.append(blade)

            # Blade Point Tip
            tip_y = 0.28 + math.cos(rad) * 0.65
            tip_x = -math.sin(rad) * 0.65
            bpy.ops.mesh.primitive_cone_add(radius1=0.15, depth=0.32, location=(tip_x, tip_y, 0.26))
            tip = bpy.context.active_object
            tip.rotation_euler = (0, 0, rad)
            tip.scale = (1.0, 0.6, 0.6)
            tip.data.materials.append(mat_blade)
            apply_uniform_clay_bevel(tip, width=0.03, segments=2)
            objs.append(tip)

            # Crossguard
            guard_y = 0.28 - math.cos(rad) * 0.35
            guard_x = math.sin(rad) * 0.35
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(guard_x, guard_y, 0.28))
            guard = bpy.context.active_object
            guard.scale = (0.46, 0.12, 0.14)
            guard.rotation_euler = (0, 0, rad)
            guard.data.materials.append(mat_guard)
            apply_uniform_clay_bevel(guard, width=0.03, segments=2)
            objs.append(guard)

            # Grip Handle
            grip_y = 0.28 - math.cos(rad) * 0.58
            grip_x = math.sin(rad) * 0.58
            bpy.ops.mesh.primitive_cylinder_add(radius=0.06, depth=0.35, vertices=12, location=(grip_x, grip_y, 0.28))
            grip = bpy.context.active_object
            grip.rotation_euler = (math.radians(90) * math.cos(rad), -math.radians(90) * math.sin(rad), rad)
            grip.data.materials.append(mat_grip)
            apply_uniform_clay_bevel(grip, width=0.02, segments=2)
            objs.append(grip)

            # Pommel
            pommel_y = 0.28 - math.cos(rad) * 0.78
            pommel_x = math.sin(rad) * 0.78
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.09, location=(pommel_x, pommel_y, 0.28))
            pommel = bpy.context.active_object
            pommel.data.materials.append(mat_pommel)
            bpy.ops.object.shade_smooth()
            objs.append(pommel)

    elif type_name == "elite":
        mat_skull = create_clay_mat("m_um_sk", (0.92, 0.88, 0.82, 1.0))
        mat_dark = create_clay_mat("m_um_skd", (0.16, 0.16, 0.22, 1.0))
        mat_horn = create_clay_mat("m_um_skh", (0.85, 0.22, 0.28, 1.0))
        mat_horn_tip = create_clay_mat("m_um_skht", (0.98, 0.80, 0.22, 1.0))

        # Skull Cranium Dome
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.62, location=(0, 0.12, 0.32))
        skull = bpy.context.active_object
        skull.scale = (1.05, 0.95, 0.85)
        skull.data.materials.append(mat_skull)
        bpy.ops.object.shade_smooth()
        objs.append(skull)

        # Upper Jaw / Teeth Block
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.32, 0.26))
        jaw = bpy.context.active_object
        jaw.scale = (0.50, 0.35, 0.32)
        jaw.data.materials.append(mat_skull)
        apply_uniform_clay_bevel(jaw, width=0.06, segments=2)
        objs.append(jaw)

        # Deep Eye Sockets (Left & Right)
        for sx in [-0.26, 0.26]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.16, depth=0.18, vertices=16, location=(sx, -0.06, 0.40))
            eye = bpy.context.active_object
            eye.data.materials.append(mat_dark)
            apply_uniform_clay_bevel(eye, width=0.03, segments=2)
            objs.append(eye)

        # Nasal Cavity
        bpy.ops.mesh.primitive_cone_add(radius1=0.08, depth=0.15, location=(0, -0.22, 0.35))
        nose = bpy.context.active_object
        nose.rotation_euler = (0, 0, math.radians(180))
        nose.data.materials.append(mat_dark)
        apply_uniform_clay_bevel(nose, width=0.02, segments=2)
        objs.append(nose)

        # Menacing Curved Horns (Left & Right)
        for hx in [-1, 1]:
            # Horn Base Segment
            bpy.ops.mesh.primitive_cone_add(radius1=0.20, depth=0.55, location=(hx * 0.52, 0.45, 0.38))
            h1 = bpy.context.active_object
            h1.rotation_euler = (math.radians(-15), math.radians(hx * 45), math.radians(hx * -35))
            h1.data.materials.append(mat_horn)
            apply_uniform_clay_bevel(h1, width=0.04, segments=2)
            objs.append(h1)

            # Horn Gold Tip
            bpy.ops.mesh.primitive_cone_add(radius1=0.12, depth=0.40, location=(hx * 0.78, 0.65, 0.48))
            h2 = bpy.context.active_object
            h2.rotation_euler = (math.radians(-25), math.radians(hx * 65), math.radians(hx * -50))
            h2.data.materials.append(mat_horn_tip)
            apply_uniform_clay_bevel(h2, width=0.03, segments=2)
            objs.append(h2)

    elif type_name == "rest":
        mat_wood = create_clay_mat("m_um_wood", (0.45, 0.28, 0.18, 1.0))
        mat_flame_out = create_clay_mat("m_um_fo", (0.95, 0.35, 0.15, 1.0), emission=(0.95, 0.35, 0.15, 1.0), emission_str=1.8)
        mat_flame_in = create_clay_mat("m_um_fi", (0.98, 0.85, 0.25, 1.0), emission=(0.98, 0.85, 0.25, 1.0), emission_str=2.8)
        mat_ember = create_clay_mat("m_um_emb", (0.98, 0.45, 0.18, 1.0), emission=(0.98, 0.45, 0.18, 1.0), emission_str=2.0)

        # 4 Criss-Cross Campfire Logs
        log_angles = [25, -65, 115, -155]
        for ang in log_angles:
            rad = math.radians(ang)
            bpy.ops.mesh.primitive_cylinder_add(radius=0.14, depth=1.05, vertices=12, location=(math.cos(rad)*0.18, math.sin(rad)*0.18, 0.18))
            log = bpy.context.active_object
            log.rotation_euler = (math.radians(90)*math.cos(rad), -math.radians(90)*math.sin(rad), rad)
            log.data.materials.append(mat_wood)
            apply_uniform_clay_bevel(log, width=0.03, segments=2)
            objs.append(log)

        # Main Outer Flame Tongue
        bpy.ops.mesh.primitive_cone_add(radius1=0.52, depth=0.95, location=(0, 0, 0.42))
        f_out = bpy.context.active_object
        f_out.scale = (1.0, 0.85, 1.0)
        f_out.data.materials.append(mat_flame_out)
        apply_uniform_clay_bevel(f_out, width=0.08, segments=3)
        objs.append(f_out)

        # Side Licking Flame Tongue
        bpy.ops.mesh.primitive_cone_add(radius1=0.32, depth=0.65, location=(0.22, -0.15, 0.38))
        f_side = bpy.context.active_object
        f_side.rotation_euler = (math.radians(15), math.radians(-20), 0)
        f_side.data.materials.append(mat_flame_out)
        apply_uniform_clay_bevel(f_side, width=0.05, segments=2)
        objs.append(f_side)

        # Bright Glowing Flame Core
        bpy.ops.mesh.primitive_cone_add(radius1=0.34, depth=0.68, location=(0, 0, 0.38))
        f_in = bpy.context.active_object
        f_in.data.materials.append(mat_flame_in)
        apply_uniform_clay_bevel(f_in, width=0.05, segments=2)
        objs.append(f_in)

        # Glowing Embers at base
        for (ex, ey) in [(-0.45, 0.35), (0.45, 0.30), (0.05, -0.48)]:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.08, location=(ex, ey, 0.20))
            emb = bpy.context.active_object
            emb.data.materials.append(mat_ember)
            bpy.ops.object.shade_smooth()
            objs.append(emb)

    elif type_name == "shop":
        mat_chest = create_clay_mat("m_um_ch", (0.55, 0.32, 0.18, 1.0))
        mat_gold = create_clay_mat("m_um_chg", (0.95, 0.78, 0.22, 1.0))
        mat_iron = create_clay_mat("m_um_chi", (0.35, 0.38, 0.45, 1.0))
        mat_ruby = create_clay_mat("m_um_chrb", (0.95, 0.25, 0.35, 1.0), emission=(0.95, 0.25, 0.35, 1.0), emission_str=1.5)

        # Treasure Chest Body
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.22))
        body = bpy.context.active_object
        body.scale = (1.10, 0.78, 0.38)
        body.data.materials.append(mat_chest)
        apply_uniform_clay_bevel(body, width=0.08, segments=3)
        objs.append(body)

        # Arched Chest Lid (Curved Cylinder)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.40, depth=1.12, vertices=16, location=(0, 0, 0.44))
        lid = bpy.context.active_object
        lid.rotation_euler = (0, math.radians(90), 0)
        lid.scale = (1.0, 0.75, 1.0)
        lid.data.materials.append(mat_chest)
        apply_uniform_clay_bevel(lid, width=0.06, segments=3)
        objs.append(lid)

        # Metal Corner Reinforcement Bands (Left & Right)
        for bx in [-0.42, 0.42]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(bx, 0, 0.32))
            band = bpy.context.active_object
            band.scale = (0.16, 0.82, 0.52)
            band.data.materials.append(mat_gold)
            apply_uniform_clay_bevel(band, width=0.03, segments=2)
            objs.append(band)

        # Front Lock Latch / Keyhole Clasp
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.41, 0.34))
        lock = bpy.context.active_object
        lock.scale = (0.24, 0.10, 0.22)
        lock.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(lock, width=0.03, segments=2)
        objs.append(lock)

        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.06, location=(0, -0.46, 0.34))
        keyhole = bpy.context.active_object
        keyhole.data.materials.append(mat_iron)
        bpy.ops.object.shade_smooth()
        objs.append(keyhole)

        # Gold Coins / Gems beside the chest
        for (cx, cy) in [(-0.68, -0.32), (-0.75, 0.15), (0.72, -0.25)]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.14, depth=0.08, vertices=12, location=(cx, cy, 0.20))
            coin = bpy.context.active_object
            coin.data.materials.append(mat_gold)
            apply_uniform_clay_bevel(coin, width=0.02, segments=2)
            objs.append(coin)

    elif type_name == "event":
        mat_q = create_clay_mat("m_um_q", (0.62, 0.28, 0.88, 1.0))
        mat_q_glow = create_clay_mat("m_um_qgl", (0.88, 0.55, 1.0, 1.0), emission=(0.88, 0.55, 1.0, 1.0), emission_str=2.0)
        mat_gold = create_clay_mat("m_um_qg", (0.95, 0.78, 0.22, 1.0))

        # Real 3D Question Mark "?" Structure
        # Upper Loop Arc
        bpy.ops.mesh.primitive_torus_add(major_radius=0.42, minor_radius=0.14, location=(0, 0.32, 0.28))
        loop = bpy.context.active_object
        loop.scale = (1.0, 0.95, 1.0)
        loop.data.materials.append(mat_q)
        bpy.ops.object.shade_smooth()
        objs.append(loop)

        # Middle Hook Stem
        bpy.ops.mesh.primitive_cylinder_add(radius=0.13, depth=0.45, vertices=16, location=(0.04, 0.05, 0.28))
        stem = bpy.context.active_object
        stem.rotation_euler = (0, 0, math.radians(25))
        stem.data.materials.append(mat_q)
        apply_uniform_clay_bevel(stem, width=0.04, segments=2)
        objs.append(stem)

        # Central mask block (cuts the left side of torus to turn loop into a clean '?')
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(-0.35, 0.22, 0.28))
        mask = bpy.context.active_object
        mask.scale = (0.35, 0.40, 0.35)
        mask.data.materials.append(mat_base)
        apply_uniform_clay_bevel(mask, width=0.04, segments=2)
        objs.append(mask)

        # Question Mark Bottom Dot
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.16, location=(0, -0.42, 0.28))
        dot = bpy.context.active_object
        dot.data.materials.append(mat_q_glow)
        bpy.ops.object.shade_smooth()
        objs.append(dot)

        # Magical Sparkle Stars
        for (sx, sy, sz) in [(-0.62, 0.45, 0.30), (0.65, 0.42, 0.30)]:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.09, location=(sx, sy, sz))
            sp = bpy.context.active_object
            sp.data.materials.append(mat_gold)
            bpy.ops.object.shade_smooth()
            objs.append(sp)

    elif type_name == "boss":
        mat_cr = create_clay_mat("m_um_cr", (0.98, 0.78, 0.15, 1.0))
        mat_cushion = create_clay_mat("m_um_cush", (0.85, 0.18, 0.25, 1.0))
        mat_ruby = create_clay_mat("m_um_crub", (0.95, 0.22, 0.35, 1.0), emission=(0.95, 0.22, 0.35, 1.0), emission_str=2.0)
        mat_pearl = create_clay_mat("m_um_cprl", (0.95, 0.95, 0.98, 1.0))

        # Royal Velvet Interior Dome Cushion
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.62, location=(0, 0, 0.28))
        cush = bpy.context.active_object
        cush.scale = (1.0, 1.0, 0.75)
        cush.data.materials.append(mat_cushion)
        bpy.ops.object.shade_smooth()
        objs.append(cush)

        # Crown Base Rim
        bpy.ops.mesh.primitive_cylinder_add(radius=0.76, depth=0.22, vertices=20, location=(0, 0, 0.20))
        band = bpy.context.active_object
        band.data.materials.append(mat_cr)
        apply_uniform_clay_bevel(band, width=0.06, segments=3)
        objs.append(band)

        # 5 Crenelated Crown Peaks (Front Center Tall, Sides Medium, Back Peaks)
        peak_angles = [0, 0.65, -0.65, 1.35, -1.35]
        for idx, ang in enumerate(peak_angles):
            px = math.sin(ang) * 0.68
            py = math.cos(ang) * 0.32 - 0.10
            h = 0.55 if idx == 0 else (0.45 if idx < 3 else 0.38)
            r = 0.18 if idx == 0 else 0.14
            bpy.ops.mesh.primitive_cone_add(radius1=r, depth=h, location=(px, py, 0.38 + h/2.0))
            pk = bpy.context.active_object
            pk.data.materials.append(mat_cr)
            apply_uniform_clay_bevel(pk, width=0.03, segments=2)
            objs.append(pk)

            # Pearl / Gem on top of each peak
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.09 if idx == 0 else 0.07, location=(px, py, 0.38 + h + 0.04))
            pearl = bpy.context.active_object
            pearl.data.materials.append(mat_ruby if idx == 0 else mat_pearl)
            bpy.ops.object.shade_smooth()
            objs.append(pearl)

        # Center Huge Ruby Medallion
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.15, location=(0, -0.72, 0.26))
        c_gem = bpy.context.active_object
        c_gem.data.materials.append(mat_ruby)
        bpy.ops.object.shade_smooth()
        objs.append(c_gem)

    return objs

def build_sokpop_active_ring():
    objs = []
    # Use lower roughness + low emission_str so top faces don't blow out
    mat_r    = create_clay_mat("m_um_ar",  (0.25, 0.88, 0.48, 1.0), roughness=0.55, emission=(0.25, 0.88, 0.48, 1.0), emission_str=0.6)
    mat_r2   = create_clay_mat("m_um_ar2", (0.42, 0.95, 0.65, 1.0), roughness=0.60, emission=(0.42, 0.95, 0.65, 1.0), emission_str=0.4)
    mat_stud = create_clay_mat("m_um_ars", (0.92, 0.96, 0.98, 1.0), roughness=0.45, emission=(0.85, 0.95, 0.90, 1.0), emission_str=0.7)

    # Outer glowing main orbit ring
    bpy.ops.mesh.primitive_torus_add(major_radius=1.35, minor_radius=0.12, location=(0, 0, 0))
    ring = bpy.context.active_object
    ring.data.materials.append(mat_r)
    bpy.ops.object.shade_smooth()
    objs.append(ring)

    # Inner secondary orbit ring (slightly smaller, different shade)
    bpy.ops.mesh.primitive_torus_add(major_radius=1.08, minor_radius=0.07, location=(0, 0, 0))
    ring2 = bpy.context.active_object
    ring2.data.materials.append(mat_r2)
    bpy.ops.object.shade_smooth()
    objs.append(ring2)

    # 4 Cardinal direction diamond studs — smaller radius to avoid big blown patches
    for ang_deg in [0, 90, 180, 270]:
        ang = math.radians(ang_deg)
        sx, sy = math.cos(ang) * 1.35, math.sin(ang) * 1.35
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.10, location=(sx, sy, 0))
        stud = bpy.context.active_object
        stud.data.materials.append(mat_stud)
        bpy.ops.object.shade_smooth()
        objs.append(stud)

    return objs

# ==================== 5. SOKPOP POWERUPS ====================

def build_sokpop_powerup(p_type):
    objs = []
    mat_gold = create_clay_mat("m_upw_g", (0.98, 0.80, 0.18, 1.0))
    mat_red = create_clay_mat("m_upw_r", (0.92, 0.32, 0.38, 1.0))
    mat_cyan = create_clay_mat("m_upw_c", (0.28, 0.72, 0.92, 1.0))
    mat_white = create_clay_mat("m_upw_w", (0.95, 0.95, 0.98, 1.0))
    mat_dark = create_clay_mat("m_upw_d", (0.28, 0.30, 0.35, 1.0))
    mat_metal = create_clay_mat("m_upw_m", (0.75, 0.78, 0.84, 1.0))
    mat_wood = create_clay_mat("m_upw_wd", (0.55, 0.35, 0.22, 1.0))

    if p_type == "star":
        star_outer = create_3d_star(r_out=1.15, r_in=0.52, depth=0.32, z_pos=0.0)
        star_outer.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(star_outer, width=0.05, segments=3)
        objs.append(star_outer)

        star_inner = create_3d_star(r_out=0.75, r_in=0.34, depth=0.14, z_pos=0.18)
        star_inner.data.materials.append(mat_white)
        apply_uniform_clay_bevel(star_inner, width=0.03, segments=2)
        objs.append(star_inner)

    elif p_type == "gold_coin":
        bpy.ops.mesh.primitive_cylinder_add(radius=1.05, depth=0.3, vertices=20, location=(0, 0, 0))
        coin = bpy.context.active_object
        coin.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(coin, width=0.08, segments=3)
        objs.append(coin)

        bpy.ops.mesh.primitive_torus_add(major_radius=0.92, minor_radius=0.08, location=(0, 0, 0.16))
        rim = bpy.context.active_object
        rim.data.materials.append(mat_gold)
        bpy.ops.object.shade_smooth()
        objs.append(rim)

        coin_star = create_3d_star(r_out=0.62, r_in=0.28, depth=0.12, z_pos=0.16)
        coin_star.data.materials.append(mat_white)
        apply_uniform_clay_bevel(coin_star, width=0.03, segments=2)
        objs.append(coin_star)

    elif p_type == "helmet":
        # 1. Helmet Dome
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.90, location=(0, -0.05, 0.15))
        h = bpy.context.active_object
        h.scale = (1.05, 1.15, 0.85)
        h.data.materials.append(mat_gold)
        bpy.ops.object.shade_smooth()
        objs.append(h)

        # 2. Central Raised Crest Ridge
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, 0.65))
        crest = bpy.context.active_object
        crest.scale = (0.20, 1.10, 0.20)
        crest.data.materials.append(mat_dark)
        apply_uniform_clay_bevel(crest, width=0.04, segments=2)
        objs.append(crest)

        # 3. Flared Contoured Brow Brim
        bpy.ops.mesh.primitive_cylinder_add(radius=0.96, depth=0.16, vertices=20, location=(0, 0.38, 0.08))
        brim = bpy.context.active_object
        brim.scale = (1.05, 0.50, 1.0)
        brim.data.materials.append(mat_dark)
        apply_uniform_clay_bevel(brim, width=0.06, segments=2)
        objs.append(brim)

        # 4. Ear Covers with Retaining Straps
        for sx in [-0.98, 0.98]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.26, depth=0.20, vertices=16, location=(sx, -0.08, 0.15))
            ear = bpy.context.active_object
            ear.rotation_euler = (0, math.radians(90), 0)
            ear.data.materials.append(mat_red)
            apply_uniform_clay_bevel(ear, width=0.05, segments=2)
            objs.append(ear)

            # Rivet
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.06, location=(sx * 1.10, -0.08, 0.15))
            rivet = bpy.context.active_object
            rivet.data.materials.append(mat_white)
            bpy.ops.object.shade_smooth()
            objs.append(rivet)

        # 5. Star Badge on Front
        top_badge = create_3d_star(r_out=0.38, r_in=0.18, depth=0.10, z_pos=0.88)
        top_badge.data.materials.append(mat_white)
        apply_uniform_clay_bevel(top_badge, width=0.02, segments=2)
        objs.append(top_badge)

    elif p_type == "bomb":
        # 1. Spherical Cast Iron Body
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.92, location=(0, -0.12, 0))
        b = bpy.context.active_object
        b.data.materials.append(mat_dark)
        bpy.ops.object.shade_smooth()
        objs.append(b)

        # 2. Threaded Brass Fuse Collar / Cap
        bpy.ops.mesh.primitive_cylinder_add(radius=0.26, depth=0.22, vertices=16, location=(0, 0.76, 0))
        c = bpy.context.active_object
        c.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(c, width=0.04, segments=2)
        objs.append(c)

        # 3. Naturally Curved Fuse Twine (Multi-Segment Arc)
        fuse_nodes = [
            (0.04, 0.94, 0.0, -15),
            (0.14, 1.12, 0.0, -35),
            (0.30, 1.25, 0.0, -60),
        ]
        for fx, fy, fz, fang in fuse_nodes:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.065, depth=0.24, vertices=12, location=(fx, fy, fz))
            fuse_seg = bpy.context.active_object
            fuse_seg.rotation_euler = (0, 0, math.radians(fang))
            fuse_seg.data.materials.append(mat_white)
            apply_uniform_clay_bevel(fuse_seg, width=0.02, segments=2)
            objs.append(fuse_seg)

        # 4. Crackling Spark Flame & Spark Beads
        mat_spark_core = create_clay_mat("m_upw_spkc", (1.0, 0.95, 0.65, 1.0), emission=(1.0, 0.95, 0.65, 1.0), emission_str=3.0)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.18, location=(0.42, 1.34, 0))
        flame = bpy.context.active_object
        flame.data.materials.append(mat_red)
        bpy.ops.object.shade_smooth()
        objs.append(flame)

        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.10, location=(0.42, 1.34, 0.06))
        spark_core = bpy.context.active_object
        spark_core.data.materials.append(mat_spark_core)
        bpy.ops.object.shade_smooth()
        objs.append(spark_core)

    elif p_type == "clock":
        # 1. Main Cylinder Body
        bpy.ops.mesh.primitive_cylinder_add(radius=1.05, depth=0.32, vertices=24, location=(0, -0.08, 0))
        clk = bpy.context.active_object
        clk.data.materials.append(mat_cyan)
        apply_uniform_clay_bevel(clk, width=0.10, segments=3)
        objs.append(clk)

        # 2. Twin Top Alarm Bells (Left & Right)
        for (bx, by, rot) in [(-0.75, 0.88, 30), (0.75, 0.88, -30)]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.32, depth=0.22, vertices=16, location=(bx, by, 0))
            bell = bpy.context.active_object
            bell.rotation_euler = (0, 0, math.radians(rot))
            bell.data.materials.append(mat_gold)
            apply_uniform_clay_bevel(bell, width=0.04, segments=2)
            objs.append(bell)

        # 3. Top Striker Button
        bpy.ops.mesh.primitive_torus_add(major_radius=0.22, minor_radius=0.06, location=(0, 1.05, 0))
        btn = bpy.context.active_object
        btn.data.materials.append(mat_gold)
        bpy.ops.object.shade_smooth()
        objs.append(btn)

        # 4. Dial Face
        bpy.ops.mesh.primitive_cylinder_add(radius=0.82, depth=0.10, vertices=24, location=(0, -0.08, 0.16))
        face = bpy.context.active_object
        face.data.materials.append(mat_white)
        objs.append(face)

        # 5. 12 Hour Dial Tick Dots
        for i in range(12):
            ang = i * (math.pi / 6.0)
            tx = math.sin(ang) * 0.68
            ty = math.cos(ang) * 0.68 - 0.08
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.035, location=(tx, ty, 0.22))
            dot = bpy.context.active_object
            dot.data.materials.append(mat_dark)
            bpy.ops.object.shade_smooth()
            objs.append(dot)

        # 6. Hour & Minute Hands
        for (hx, hy, hl, ang) in [(-0.14, 0.12, 0.40, -40), (0.16, 0.12, 0.48, 45)]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.045, depth=hl, vertices=8, location=(hx, hy - 0.08, 0.23))
            h = bpy.context.active_object
            h.rotation_euler = (0, 0, math.radians(ang))
            h.data.materials.append(mat_dark)
            objs.append(h)

        # Center Pin Cap
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.08, location=(0, -0.08, 0.25))
        pin = bpy.context.active_object
        pin.data.materials.append(mat_red)
        bpy.ops.object.shade_smooth()
        objs.append(pin)

    elif p_type == "shovel":
        # 1. Beveled Spade Scoop Blade
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.28, 0))
        b = bpy.context.active_object
        b.scale = (1.10, 0.95, 0.22)
        b.data.materials.append(mat_metal)
        apply_uniform_clay_bevel(b, width=0.10, segments=3)
        objs.append(b)

        # Tapered Spade Point
        bpy.ops.mesh.primitive_cone_add(radius1=0.55, depth=0.52, location=(0, -0.85, 0))
        cone = bpy.context.active_object
        cone.rotation_euler = (0, 0, math.radians(180))
        cone.scale = (1.0, 0.55, 0.45)
        cone.data.materials.append(mat_metal)
        apply_uniform_clay_bevel(cone, width=0.05, segments=2)
        objs.append(cone)

        # Center Reinforcing Spine Ridge
        bpy.ops.mesh.primitive_cylinder_add(radius=0.10, depth=1.05, vertices=12, location=(0, -0.42, 0.12))
        spine = bpy.context.active_object
        spine.data.materials.append(mat_metal)
        apply_uniform_clay_bevel(spine, width=0.03, segments=2)
        objs.append(spine)

        # 2. Steel Collar Sleeve Socket
        bpy.ops.mesh.primitive_cylinder_add(radius=0.16, depth=0.35, vertices=16, location=(0, 0.25, 0))
        collar = bpy.context.active_object
        collar.data.materials.append(mat_metal)
        apply_uniform_clay_bevel(collar, width=0.04, segments=2)
        objs.append(collar)

        # 3. Wooden Shaft
        bpy.ops.mesh.primitive_cylinder_add(radius=0.11, depth=0.85, vertices=12, location=(0, 0.68, 0))
        handle = bpy.context.active_object
        handle.data.materials.append(mat_wood)
        apply_uniform_clay_bevel(handle, width=0.03, segments=2)
        objs.append(handle)

        # 4. Ergonomic D-Grip Handle (Torus + Cross-Bar)
        bpy.ops.mesh.primitive_torus_add(major_radius=0.26, minor_radius=0.07, location=(0, 1.18, 0))
        d_grip = bpy.context.active_object
        d_grip.data.materials.append(mat_red)
        bpy.ops.object.shade_smooth()
        objs.append(d_grip)

        bpy.ops.mesh.primitive_cylinder_add(radius=0.065, depth=0.45, vertices=12, location=(0, 1.18, 0))
        d_bar = bpy.context.active_object
        d_bar.rotation_euler = (0, math.radians(90), 0)
        d_bar.data.materials.append(mat_wood)
        apply_uniform_clay_bevel(d_bar, width=0.02, segments=2)
        objs.append(d_bar)

    elif p_type == "life":
        # Sculpted Organic Clay Heart
        for sx in [-0.38, 0.38]:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.55, location=(sx, 0.25, 0))
            sph = bpy.context.active_object
            sph.scale = (1.0, 1.0, 0.75)
            sph.data.materials.append(mat_red)
            bpy.ops.object.shade_smooth()
            objs.append(sph)

        bpy.ops.mesh.primitive_cone_add(radius1=0.78, depth=1.18, location=(0, -0.32, 0))
        cone = bpy.context.active_object
        cone.rotation_euler = (0, 0, math.radians(180))
        cone.scale = (1.0, 0.85, 0.75)
        cone.data.materials.append(mat_red)
        apply_uniform_clay_bevel(cone, width=0.14, segments=3)
        objs.append(cone)

        # Glossy White Clay Reflection Highlight
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.14, location=(-0.35, 0.45, 0.32))
        hl = bpy.context.active_object
        hl.scale = (1.0, 1.0, 0.6)
        hl.data.materials.append(mat_white)
        bpy.ops.object.shade_smooth()
        objs.append(hl)

    return objs

# ==================== 6. SOKPOP VFX ====================

# 爆炸每一帧的形状参数。写成显式表格而不是 `0.38 + frame_idx * 0.24` 这种公式,
# 是因为爆炸的节奏本来就不是线性的 —— 它必须"冲上去再散开"。
#
# 老版本的毛病就出在那个单调递增的公式上: 半径一路涨到 1.58, 到 f4/f5 时几个
# 球大到互相吞掉, 糊成一整颗带明暗分界线的大球 —— 读起来是"一颗球", 不是烟。
# 而且轮廓一直在变大, 于是爆炸永远不会"消散", 只会越来越胖然后被整帧切掉。
#
# 现在的关键是 r_puff 在 f2 之后*反过来变小*, 而 span 继续微涨: 团块因此裂成
# 一圈互相分开的小球, 总墨量 (n * r_puff^2) 从 f2 的 1.20 一路掉到 f5 的 0.23。
# 那才是消散。中心留空也是同理 —— 空心环不会被读成实心球。
#
# `inner` 是第二圈 puff (半径 0.45*span)。没有它的时候 f2/f3 会渲成一圈分开的
# 珠子中间浮一个小黄点 —— 读起来是项链, 不是火球。中心必须在燃烧阶段是*实*的,
# 空心环只属于最后两帧的烟。
EXPLOSION_FRAMES = [
    # span    r_puff  n   inner fire  glow  core  spikes spike_len
    dict(span=0.26, r_puff=0.30, n=6,  inner=0, fire=1.00, glow=3.0, core=0.30, spikes=6, spike_len=0.55),  # f0 起爆: 紧、白热、带尖刺
    dict(span=0.55, r_puff=0.34, n=8,  inner=5, fire=1.00, glow=2.6, core=0.32, spikes=6, spike_len=0.80),  # f1 急速膨胀, 最亮
    dict(span=0.82, r_puff=0.33, n=11, inner=6, fire=0.80, glow=1.6, core=0.28, spikes=4, spike_len=0.55),  # f2 火球最大
    dict(span=0.95, r_puff=0.28, n=13, inner=5, fire=0.42, glow=0.8, core=0.20, spikes=0, spike_len=0.0),   # f3 火退回中心, 烟接管
    dict(span=1.00, r_puff=0.22, n=14, inner=0, fire=0.14, glow=0.0, core=0.0,  spikes=0, spike_len=0.0),   # f4 烟环, 中心掏空
    dict(span=1.05, r_puff=0.15, n=10, inner=0, fire=0.00, glow=0.0, core=0.0,  spikes=0, spike_len=0.0),   # f5 散开
]


def _puff_wobble(seed, span):
    """给 puff 环加一点确定性的不规则。

    完美的圆环读起来是机械的; 黏土爆炸得是歪的。用整数散列而不是 random 是为了
    可复现 —— 同样的 frame_idx 永远渲出同样的图。
    """
    h = (seed * 2654435761) % 1000
    return (h / 1000.0 - 0.5) * span * 0.42


def build_sokpop_explosion(frame_idx):
    objs = []
    cfg = EXPLOSION_FRAMES[frame_idx]
    glow = cfg["glow"]

    # 火焰带自发光: 这个管线用的是 Standard view transform + 刻意压平的光照,
    # 靠明暗是拉不出"烫"的感觉的, 热度只能靠 emission 给。烟不发光。
    mat_fire = create_clay_mat(
        f"m_uexp_f{frame_idx}", (0.98, 0.42, 0.12, 1.0),
        emission=(1.0, 0.46, 0.10, 1.0), emission_str=max(0.0, glow * 0.30))
    # 别把这个调太白: (1.0,0.90,0.42) 配 emission 2.6 会烧成一大片奶白, 在
    # 橘色火球中间读起来像个洞, 不像高温。饱和的金黄 + 收敛的自发光才是热。
    mat_hot = create_clay_mat(
        f"m_uexp_h{frame_idx}", (1.0, 0.82, 0.28, 1.0),
        emission=(1.0, 0.84, 0.34, 1.0), emission_str=glow * 0.55)
    mat_smoke = create_clay_mat(f"m_uexp_s{frame_idx}", (0.86, 0.82, 0.79, 1.0))
    mat_dark  = create_clay_mat(f"m_uexp_d{frame_idx}", (0.42, 0.39, 0.44, 1.0))

    span = cfg["span"]
    n = cfg["n"]
    for i in range(n):
        ang = i * (2.0 * math.pi / float(n)) + frame_idx * 0.27
        d = span + _puff_wobble(i + frame_idx * 17, span)
        r = cfg["r_puff"] * (1.0 + (0.16 if i % 3 == 0 else -0.10))
        # 火和烟交错分布而不是"前一半火后一半烟", 免得出现一半橘一半灰的分界
        is_fire = ((i * 7) % 10) < int(cfg["fire"] * 10.0)
        if is_fire:
            # mat_hot 只点缀极少数几个。给多了会渲成一堆奶白色球混在橘色里,
            # 像爆米花而不是火。
            mat = mat_hot if (glow > 2.0 and i % 6 == 0) else mat_fire
        else:
            mat = mat_dark if i % 3 == 0 else mat_smoke
        bpy.ops.mesh.primitive_uv_sphere_add(
            radius=r, location=(math.cos(ang) * d, math.sin(ang) * d, (i % 3 - 1) * 0.06))
        sph = bpy.context.active_object
        sph.data.materials.append(mat)
        bpy.ops.object.shade_smooth()
        objs.append(sph)

    # 内圈: 把中心填实, 顺便让团块变得凹凸不平而不是一颗光滑大球
    for i in range(cfg["inner"]):
        ang = i * (2.0 * math.pi / float(cfg["inner"])) - frame_idx * 0.41
        d = span * 0.45 + _puff_wobble(i * 3 + frame_idx * 11, span) * 0.5
        r = cfg["r_puff"] * (0.92 if i % 2 == 0 else 0.78)
        mat = mat_fire if ((i * 3) % 10) < int(cfg["fire"] * 10.0) else mat_smoke
        bpy.ops.mesh.primitive_uv_sphere_add(
            radius=r, location=(math.cos(ang) * d, math.sin(ang) * d, 0.05))
        sph = bpy.context.active_object
        sph.data.materials.append(mat)
        bpy.ops.object.shade_smooth()
        objs.append(sph)

    # 白热核心。f4/f5 没有 (core=0), 中心就此掏空 —— 这正是烟环该有的样子。
    if cfg["core"] > 0.0:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=cfg["core"], location=(0, 0, 0.10))
        core = bpy.context.active_object
        core.data.materials.append(mat_hot if glow > 1.0 else mat_fire)
        bpy.ops.object.shade_smooth()
        objs.append(core)

    # 放射状尖刺: 只在头两三帧出现, 是"炸开的一瞬间"的读法。
    # 老版本把它们摆在 0.48*scale, 全被火球吞了, 等于没画。
    for i in range(cfg["spikes"]):
        ang = i * (2.0 * math.pi / float(cfg["spikes"])) + frame_idx * 0.5
        ln = cfg["spike_len"]
        # 圆锥以中心定位、沿轴向伸出 depth, 所以尖端在 d + ln/2。把中心放在
        # span + ln/2 上, 尖端正好落在 span + ln —— 这样 spike_len 就是"露在
        # 火球外面多长", 可以直接对着画幅半宽 (ortho/2) 验有没有出框。
        d = span + ln * 0.5
        bpy.ops.mesh.primitive_cone_add(
            radius1=0.11, depth=ln,
            location=(math.cos(ang) * d, math.sin(ang) * d, 0))
        shard = bpy.context.active_object
        shard.rotation_euler = (math.radians(90), 0, ang + math.pi / 2)
        shard.data.materials.append(mat_hot)
        apply_uniform_clay_bevel(shard, width=0.02, segments=2)
        objs.append(shard)

    return objs


def build_sokpop_spawn_star(frame_idx):
    objs = []
    mat_star = create_clay_mat("m_ustar", (0.98, 0.82, 0.22, 1.0), emission=(0.98, 0.82, 0.22, 1.0), emission_str=2.0)
    mat_core = create_clay_mat("m_ustarc", (1.0, 0.98, 0.80, 1.0), emission=(1.0, 0.98, 0.80, 1.0), emission_str=3.0)
    rot = frame_idx * (math.pi / 6.0)
    scale_factor = 0.45 + math.sin(frame_idx * (math.pi / 3.0)) * 0.35
    for i in range(4):
        angle = rot + i * (math.pi / 2.0)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.16 * scale_factor, depth=1.6 * scale_factor, vertices=10, location=(0, 0, 0))
        pt = bpy.context.active_object
        pt.rotation_euler = (math.radians(90), 0, angle)
        pt.data.materials.append(mat_star)
        apply_uniform_clay_bevel(pt, width=0.04, segments=2)
        objs.append(pt)

    # Bright central glow core
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.28 * scale_factor, location=(0, 0, 0))
    core = bpy.context.active_object
    core.data.materials.append(mat_core)
    bpy.ops.object.shade_smooth()
    objs.append(core)
    return objs

def build_sokpop_bullet(is_plasma=False):
    objs = []
    if not is_plasma:
        # Regular Shell: beveled oval cannonball shape
        mat_shell  = create_clay_mat("m_ubull_s", (0.92, 0.50, 0.20, 1.0))
        mat_tip    = create_clay_mat("m_ubull_t", (0.85, 0.85, 0.90, 1.0))
        mat_base   = create_clay_mat("m_ubull_b", (0.32, 0.32, 0.38, 1.0))
        mat_band   = create_clay_mat("m_ubull_bd", (0.95, 0.78, 0.22, 1.0))

        # Oval body
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.48, location=(0, 0, 0))
        body = bpy.context.active_object
        body.scale = (1.0, 0.78, 1.0)
        body.data.materials.append(mat_shell)
        bpy.ops.object.shade_smooth()
        objs.append(body)

        # Pointed steel cap tip
        bpy.ops.mesh.primitive_cone_add(radius1=0.32, depth=0.52, location=(0, 0.46, 0))
        tip = bpy.context.active_object
        tip.rotation_euler = (math.radians(90), 0, 0)
        tip.scale = (1.0, 1.0, 0.85)
        tip.data.materials.append(mat_tip)
        apply_uniform_clay_bevel(tip, width=0.04, segments=2)
        objs.append(tip)

        # Flat brass base cap
        bpy.ops.mesh.primitive_cylinder_add(radius=0.38, depth=0.16, vertices=14, location=(0, -0.45, 0))
        base_cap = bpy.context.active_object
        base_cap.rotation_euler = (math.radians(90), 0, 0)
        base_cap.data.materials.append(mat_base)
        apply_uniform_clay_bevel(base_cap, width=0.04, segments=2)
        objs.append(base_cap)

        # Gold driving band ring at equator
        bpy.ops.mesh.primitive_torus_add(major_radius=0.50, minor_radius=0.06, location=(0, 0, 0))
        band = bpy.context.active_object
        band.rotation_euler = (math.radians(90), 0, 0)
        band.data.materials.append(mat_band)
        bpy.ops.object.shade_smooth()
        objs.append(band)

    else:
        # Plasma Bolt: cyan teardrop body + energy coil rings + glowing core
        mat_plasma = create_clay_mat("m_ubull_pl", (0.28, 0.88, 1.0, 1.0), emission=(0.28, 0.88, 1.0, 1.0), emission_str=3.5)
        mat_core   = create_clay_mat("m_ubull_plc", (0.85, 0.98, 1.0, 1.0), emission=(0.85, 0.98, 1.0, 1.0), emission_str=5.0)
        mat_tail   = create_clay_mat("m_ubull_plt", (0.15, 0.55, 0.82, 1.0), emission=(0.15, 0.55, 0.82, 1.0), emission_str=2.0)

        # Elongated teardrop body
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.50, location=(0, 0, 0))
        body = bpy.context.active_object
        body.scale = (1.0, 1.38, 1.0)
        body.data.materials.append(mat_plasma)
        bpy.ops.object.shade_smooth()
        objs.append(body)

        # Bright glowing core
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.28, location=(0, 0.05, 0))
        core = bpy.context.active_object
        core.data.materials.append(mat_core)
        bpy.ops.object.shade_smooth()
        objs.append(core)

        # 3 Energy coil rings along the tail
        for ry in [-0.18, -0.40, -0.60]:
            bpy.ops.mesh.primitive_torus_add(major_radius=0.38 + abs(ry) * 0.2, minor_radius=0.055, location=(0, ry, 0))
            coil = bpy.context.active_object
            coil.rotation_euler = (math.radians(90), 0, 0)
            coil.data.materials.append(mat_tail)
            bpy.ops.object.shade_smooth()
            objs.append(coil)

    return objs

# ==================== MASTER BATCH RENDER ====================

# ==================== 坦克调色板 (模块级, 供定向重渲复用) ====================
# 这两张表以前是 main() 里的局部变量, 于是"只重渲某一种坦克"就无处下手 ——
# 只能整脚本跑一遍, 把 240 帧连同工作区里尚未提交的改动一起覆盖掉。
# 提到模块级后, tools/rerender_tanks.py 可以直接 import 这份唯一的真源, 按名字
# 渲染子集, 不必复制一份会和这里发散的调色板。
#
# 色相分配 (避免任何两个单位在战场上撞色):
#   玩家 P1  黄 / 橙 / 绿 / 蓝      玩家 P2  绿-青系
#   enemy_fast 青   enemy_power 红   enemy_armor 深绿   enemy_train 暗紫灰
#   enemy_basic 紫罗兰 —— 见下方注释
PLAYER_PALETTES = {
    "player_tier0": {"body": (0.98, 0.80, 0.22, 1.0), "turret": (1.0, 0.86, 0.35, 1.0), "trim": (0.38, 0.75, 0.45, 1.0), "b_cnt": 1, "blen": 0.95, "bthick": 0.19, "heavy": False, "plasma": False},
    "player_tier1": {"body": (0.98, 0.58, 0.26, 1.0), "turret": (1.0, 0.70, 0.36, 1.0), "trim": (0.98, 0.38, 0.48, 1.0), "b_cnt": 1, "blen": 1.18, "bthick": 0.20, "heavy": False, "plasma": False},
    "player_tier2": {"body": (0.38, 0.78, 0.45, 1.0), "turret": (0.48, 0.85, 0.55, 1.0), "trim": (0.98, 0.80, 0.25, 1.0), "b_cnt": 2, "blen": 1.08, "bthick": 0.16, "heavy": True, "plasma": False},
    "player_tier3": {"body": (0.28, 0.62, 0.95, 1.0), "turret": (0.38, 0.72, 0.98, 1.0), "trim": (0.98, 0.82, 0.22, 1.0), "b_cnt": 1, "blen": 1.25, "bthick": 0.24, "heavy": True, "plasma": True},
}

ENEMY_PALETTES = {
    # enemy_basic 原本是 (0.75, 0.78, 0.84) 近中性灰蓝, 实测饱和度 15.3% ——
    # 全部 30 组坦克里最低的一组, 而它偏偏是出场次数最多的敌人。它压在灰紫色
    # tile_steel 和灰白砖缝上时几乎没有色相分离, 也和"靠敌人种类而不是隐藏数值
    # 区分难度"的原则相悖: baseline 敌人首先得是个一眼能认出的剪影。
    # 改用紫罗兰: 玩家占了黄/橙/绿/蓝, 其余敌人占了青/红/深绿, 地形占了赤陶橙、
    # 浅薰衣草灰、沙黄、冰蓝、树绿 —— 紫罗兰是唯一没被占用又不会和地形撞的色相,
    # 且明度压得比 tile_steel 低, 即使在紫灰色钢墙前也有明暗分离。
    # 描边沿用金色: enemy_power / enemy_armor 都是金/黄描边, 这是既有的"敌方"语汇。
    "enemy_basic": {"body": (0.54, 0.36, 0.74, 1.0), "turret": (0.64, 0.47, 0.84, 1.0), "trim": (0.98, 0.80, 0.30, 1.0), "b_cnt": 1, "blen": 0.92, "bthick": 0.16, "heavy": False},
    "enemy_fast": {"body": (0.26, 0.75, 0.88, 1.0), "turret": (0.42, 0.82, 0.95, 1.0), "trim": (0.98, 0.95, 0.95, 1.0), "b_cnt": 1, "blen": 1.15, "bthick": 0.15, "heavy": False},
    "enemy_power": {"body": (0.92, 0.32, 0.38, 1.0), "turret": (0.98, 0.45, 0.48, 1.0), "trim": (0.98, 0.82, 0.22, 1.0), "b_cnt": 1, "blen": 1.25, "bthick": 0.22, "heavy": False},
    "enemy_armor": {"body": (0.28, 0.62, 0.38, 1.0), "turret": (0.38, 0.72, 0.48, 1.0), "trim": (0.90, 0.85, 0.35, 1.0), "b_cnt": 1, "blen": 1.18, "bthick": 0.24, "heavy": True},
}


def main():
    clear_scene()
    setup_render_settings(rx=256, ry=256)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
    reset_jitter_seed(1000)

    print(">>> 1. Rendering Unified Sokpop Tanks (6-Frame Smooth Loop, Ortho Scale 3.6)...")
    player_palettes = PLAYER_PALETTES
    for name, cfg in player_palettes.items():
        for frame in range(6):
            objs = build_sokpop_tank(
                f"{name}_f{frame}", cfg["body"], cfg["turret"], cfg["trim"],
                barrel_count=cfg["b_cnt"], barrel_len=cfg["blen"], barrel_thick=cfg["bthick"],
                is_heavy=cfg["heavy"], is_plasma=cfg["plasma"], frame=frame
            )
            render_and_clean(objs, os.path.join(SPRITES_TANKS, f"{name}_f{frame}.png"))

    enemies = ENEMY_PALETTES
    for name, cfg in enemies.items():
        for frame in range(6):
            objs = build_sokpop_tank(
                f"{name}_f{frame}", cfg["body"], cfg["turret"], cfg["trim"],
                barrel_count=cfg["b_cnt"], barrel_len=cfg["blen"], barrel_thick=cfg["bthick"],
                is_heavy=cfg["heavy"], frame=frame
            )
            render_and_clean(objs, os.path.join(SPRITES_TANKS, f"{name}_f{frame}.png"))

    print(">>> 2. Rendering Unified Sokpop Tiles (6-Frame Water Flow, Ortho Scale 3.3)...")
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
    tiles = {
        "tile_brick.png": build_sokpop_brick,
        "tile_steel.png": build_sokpop_steel,
        "tile_trees.png": build_sokpop_trees,
        "tile_ice.png": build_sokpop_ice,
        "base_eagle.png": lambda: build_sokpop_eagle(False),
        "base_destroyed.png": lambda: build_sokpop_eagle(True),
    }
    for fname, builder in tiles.items():
        objs = builder()
        render_and_clean(objs, os.path.join(SPRITES_TILES, fname))

    # 6-Frame Continuous Looping Water River
    for w_f in range(6):
        objs = build_sokpop_water(w_f)
        render_and_clean(objs, os.path.join(SPRITES_TILES, f"tile_water_f{w_f}.png"))

    print(">>> 3. Rendering Unified Sokpop Buildings...")
    render_and_clean(build_sokpop_turret_base(), os.path.join(SPRITES_BUILDINGS, "turret_base.png"))
    render_and_clean(build_sokpop_turret_gun(), os.path.join(SPRITES_BUILDINGS, "turret_gun.png"))
    render_and_clean(build_sokpop_fortified_wall(), os.path.join(SPRITES_BUILDINGS, "fortified_wall.png"))
    render_and_clean(build_sokpop_landmine(), os.path.join(SPRITES_BUILDINGS, "landmine.png"))
    render_and_clean(build_sokpop_repair_station(), os.path.join(SPRITES_BUILDINGS, "repair_station.png"))

    print(">>> 4. Rendering Unified Sokpop Power-Ups & Gold Coin...")
    for p in ["star", "bomb", "clock", "helmet", "shovel", "life", "gold_coin"]:
        render_and_clean(build_sokpop_powerup(p), os.path.join(SPRITES_POWERUPS, f"{p}.png" if p != "gold_coin" else "gold_coin.png"))

    print(">>> 5. Rendering Unified Sokpop VFX (Explosions 6f, Stars 6f, Projectiles)...")
    for e_idx in range(6):
        render_and_clean(build_sokpop_explosion(e_idx), os.path.join(SPRITES_EFFECTS, f"explosion_{e_idx}.png"))
    for s_idx in range(6):
        render_and_clean(build_sokpop_spawn_star(s_idx), os.path.join(SPRITES_EFFECTS, f"spawn_star_{s_idx}.png"))
    render_and_clean(build_sokpop_bullet(False), os.path.join(SPRITES_EFFECTS, "bullet.png"))
    render_and_clean(build_sokpop_bullet(True), os.path.join(SPRITES_EFFECTS, "bullet_plasma.png"))

    print(">>> 6. Rendering High-Contrast Sokpop Map Nodes...")
    for node_type in ["battle", "elite", "rest", "shop", "event", "boss"]:
        render_and_clean(build_sokpop_map_node(node_type), os.path.join(SPRITES_MAP, f"node_{node_type}.png"))
    create_sokpop_lighting(ortho_scale=4.2, sun_energy=1.4)  # Wider frame, dimmer sun for glow-heavy ring
    render_and_clean(build_sokpop_active_ring(), os.path.join(SPRITES_MAP, "node_active_ring.png"))
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)

    # Master .blend clean and save
    for mat in list(bpy.data.materials):
        if mat.users == 0:
            bpy.data.materials.remove(mat)

    coll_tanks = bpy.data.collections.new("Sokpop_Clay_Tanks")
    coll_tiles = bpy.data.collections.new("Sokpop_Clay_Tiles")
    bpy.context.scene.collection.children.link(coll_tanks)
    bpy.context.scene.collection.children.link(coll_tiles)

    p_showcase = build_sokpop_tank("ShowcaseSokpopTank", (0.98, 0.80, 0.22, 1.0), (1.0, 0.86, 0.35, 1.0), (0.38, 0.75, 0.45, 1.0), 1, 1.1, 0.2, False, False)
    for obj in p_showcase: coll_tanks.objects.link(obj)

    t_showcase = build_sokpop_eagle(False)
    for obj in t_showcase:
        obj.location.x += 4.0
        coll_tiles.objects.link(obj)

    os.makedirs(os.path.dirname(BLENDER_SAVE), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLENDER_SAVE)
    print(f"Master Clean .blend Saved: {BLENDER_SAVE}")

if __name__ == "__main__":
    main()
