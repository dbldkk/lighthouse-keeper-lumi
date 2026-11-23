"""Охотник («тот, кто ходит»): худое вытянутое существо в истлевшем плаще смотрителя.
Строится целиком из Python в Blender (headless):
  blender -b -P tools/blender/hunter_build.py -- [--render DIR]
Результат: assets/source_blender/hunter/hunter.blend и assets/models/characters/hunter/hunter.glb
Модель: скелетный граф → Skin + Subsurf → рёбра, позвонки, глазницы, зубы, когти; плащ из рваных полос.
Цвет — в вершинах (бледная мокрая кожа утопленника, тёмные конечности, вены). Риг из 40 костей,
анимации: idle, stalk, lurch, search, grab, door_wait.
"""
import bpy, bmesh, math, os, sys, random
from mathutils import Vector, Matrix, Euler, noise

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BLEND = os.path.join(ROOT, "assets/source_blender/hunter/hunter.blend")
GLB = os.path.join(ROOT, "assets/models/characters/hunter/hunter.glb")
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
RENDER = args[args.index("--render") + 1] if "--render" in args else ""
random.seed(1979)
FPS = 30

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = FPS

def V(*a):
    return Vector(a)

# ---------------------------------------------------------------- скелетный граф тела
# Смотрит в −Y (в Godot это +Z). Сутулая поза покоя: спина горбом, голова вынесена вперёд и вниз.
P = {}
R = {}
E = []
def node(name, pos, rx, ry=None):
    P[name] = V(*pos); R[name] = (rx, ry if ry is not None else rx)
def link(*names):
    for a, b in zip(names, names[1:]):
        E.append((a, b))

node("pelvis", (0, .03, 1.22), .15, .115)
node("waist", (0, -.01, 1.42), .105, .085)
node("ribs_low", (0, -.09, 1.63), .165, .125)
node("ribs_high", (0, -.21, 1.87), .19, .14)
node("chest_top", (0, -.36, 2.06), .17, .13)
node("neck_base", (0, -.49, 2.16), .07, .065)
node("neck_mid", (0, -.62, 2.2), .05, .05)
node("head_back", (0, -.72, 2.225), .095, .105)
node("head_mid", (0, -.84, 2.2), .09, .095)
node("face", (0, -.96, 2.14), .065, .075)
node("snout", (0, -1.04, 2.085), .04, .04)
node("jaw_root", (0, -.8, 2.12), .055, .045)
node("jaw_mid", (0, -.9, 2.0), .048, .036)
node("jaw_tip", (0, -.99, 1.93), .032, .026)
link("pelvis", "waist", "ribs_low", "ribs_high", "chest_top", "neck_base", "neck_mid", "head_back", "head_mid", "face", "snout")
link("head_back", "jaw_root", "jaw_mid", "jaw_tip")

def limb_side(s):
    x = s  # +1 левая (x>0), −1 правая
    L = "L" if s > 0 else "R"
    node("clav." + L, (.19 * x, -.33, 2.08), .065, .055)
    node("shoulder." + L, (.34 * x, -.34, 2.05), .07, .065)
    node("bicep." + L, (.38 * x, -.38, 1.8), .052, .048)
    node("elbow." + L, (.42 * x, -.43, 1.5), .042, .04)
    node("forearm." + L, (.44 * x, -.5, 1.15), .044, .036)
    node("wrist." + L, (.45 * x, -.58, .83), .028, .024)
    node("palm." + L, (.46 * x, -.62, .7), .048, .022)
    link("chest_top", "clav." + L, "shoulder." + L, "bicep." + L, "elbow." + L, "forearm." + L, "wrist." + L, "palm." + L)
    for i, (fx, fy) in enumerate([(.4, -.6), (.44, -.68), (.49, -.7), (.53, -.66)]):
        k = "fk%d.%s" % (i, L); t = "ft%d.%s" % (i, L)
        node(k, (fx * x, fy - .02, .5), .017, .015)
        node(t, ((fx + (i - 1.5) * .025) * x, fy - .08, .27 - abs(i - 1.5) * .03), .006, .006)
        link("palm." + L, k, t)
    node("thk." + L, (.41 * x, -.6, .62), .016, .014)
    node("tht." + L, (.38 * x, -.68, .46), .006, .006)
    link("palm." + L, "thk." + L, "tht." + L)
    node("hip." + L, (.13 * x, .02, 1.2), .08, .075)
    node("thigh." + L, (.17 * x, -.1, .98), .07, .065)
    node("knee." + L, (.19 * x, -.2, .72), .05, .05)
    node("shin." + L, (.19 * x, -.06, .42), .038, .038)
    node("ankle." + L, (.19 * x, .09, .14), .03, .03)
    node("ball." + L, (.19 * x, -.12, .05), .04, .024)
    link("pelvis", "hip." + L, "thigh." + L, "knee." + L, "shin." + L, "ankle." + L, "ball." + L)
    for i, dx in enumerate([-.045, 0, .045]):
        t = "toe%d.%s" % (i, L)
        node(t, ((.19 + dx) * x, -.31, .025), .007, .007)
        link("ball." + L, t)

limb_side(1); limb_side(-1)

names = list(P.keys())
idx = {n: i for i, n in enumerate(names)}
mesh = bpy.data.meshes.new("HunterBody")
mesh.from_pydata([P[n] for n in names], [(idx[a], idx[b]) for a, b in E], [])
body = bpy.data.objects.new("HunterBody", mesh)
scene.collection.objects.link(body)
bpy.context.view_layer.objects.active = body
body.select_set(True)
skin = body.modifiers.new("Skin", "SKIN")
skin.branch_smoothing = .6
skin.use_smooth_shade = True
for n in names:
    d = mesh.skin_vertices[0].data[idx[n]]
    d.radius = R[n]
mesh.skin_vertices[0].data[idx["pelvis"]].use_root = True
sub = body.modifiers.new("Subsurf", "SUBSURF")
sub.levels = 2
sub.render_levels = 2
bpy.ops.object.modifier_apply(modifier="Skin")
bpy.ops.object.modifier_apply(modifier="Subsurf")

# ---------------------------------------------------------------- лепка: рёбра, впалый живот, глазницы, шум кожи
SPINE = [P[n] for n in ["pelvis", "waist", "ribs_low", "ribs_high", "chest_top", "neck_base"]]

def spine_frame(p):
    """Ближайшая точка на оси корпуса, параметр по длине, направление."""
    best = None
    acc = 0.0
    for a, b in zip(SPINE, SPINE[1:]):
        ab = b - a
        t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
        q = a + ab * t
        d = (p - q).length
        if best is None or d < best[0]:
            best = (d, q, acc + ab.length * t, ab.normalized())
        acc += ab.length
    return best

bm = bmesh.new()
bm.from_mesh(mesh)
bm.verts.ensure_lookup_table()
bm.normal_update()
eye_pos = {s: V(.046 * s, -.975, 2.165) for s in (1, -1)}
for v in bm.verts:
    p = v.co.copy()
    n = v.normal.copy()
    d, q, s_len, axis = spine_frame(p)
    radial = (p - q)
    if radial.length > 1e-5 and abs(p.x) < .32 and d < .32:
        radial.normalize()
        back = Vector((0, axis.z, -axis.y)).normalized() if axis.y < 0 else Vector((0, 1, 0))
        # рёбра на груди и боках (не на спине)
        frontness = -radial.dot(back)
        if .48 < s_len < .92 and frontness > -.35:
            phase = (s_len - .48) / .062
            ridge = max(0.0, math.sin(phase * math.pi)) ** 3
            v.co += radial * (.014 * ridge - .006) * min(1.0, frontness + .6)
        # впалый живот под рёбрами
        if .12 < s_len < .45 and frontness > .2:
            v.co -= radial * .022 * math.sin((s_len - .12) / .33 * math.pi) * frontness
    # глазницы
    for s, e in eye_pos.items():
        k = (p - e).length
        if k < .042:
            v.co -= n * .02 * (1 - k / .042) ** 1.5
    # кожа: мелкие бугры
    v.co += n * noise.noise(p * 9.0) * .006
bm.to_mesh(mesh)
bm.free()
mesh.update()

# ---------------------------------------------------------------- позвонки, зубы, глаза
parts = []
def ico(name, at, r, sub=2, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub, radius=r, location=at)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    return o

def cone(name, at, direction, r, length):
    bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=r, radius2=0, depth=length, location=at)
    o = bpy.context.active_object
    o.name = name
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(direction.normalized())
    o.location = at + direction.normalized() * length * .5
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return o

chain = SPINE + [P["neck_mid"]]
vert_parts = []
for i in range(1, 12):
    t = i / 12 * (len(chain) - 1)
    a = chain[int(t)]; b = chain[min(int(t) + 1, len(chain) - 1)]
    q = a.lerp(b, t - int(t))
    axis = (b - a).normalized()
    back = Vector((0, axis.z, -axis.y)).normalized()
    names_r = [R[n][1] for n in ["pelvis", "waist", "ribs_low", "ribs_high", "chest_top", "neck_base", "neck_mid"]]
    rr = names_r[int(t)] * (1 - (t - int(t))) + names_r[min(int(t) + 1, 6)] * (t - int(t))
    vert_parts.append(ico("Vertebra%d" % i, q + back * (rr * .93), .026 + .008 * math.sin(i / 11 * math.pi), 2, (1.2, 1, .8)))

teeth = []
for i in range(9):
    u = (i - 4) / 4.0
    # верхний ряд — по краю морды, вниз
    at = V(u * .042, -1.0 + abs(u) * .07, 2.075 - abs(u) * .01)
    teeth.append(cone("ToothU%d" % i, at, V(0, -.15, -1), .007, .035 + .012 * random.random()))
    at = V(u * .034, -.955 + abs(u) * .06, 1.965 + abs(u) * .03)
    teeth.append(cone("ToothL%d" % i, at, V(0, -.2, 1), .006, .028 + .01 * random.random()))
eyes = [ico("Eye.L", eye_pos[1] + V(0, -.004, 0), .017, 2), ico("Eye.R", eye_pos[-1] + V(0, -.004, 0), .017, 2)]

# ---------------------------------------------------------------- плащ: истлевший непромокаемый плащ смотрителя
CLOAK_AXIS = [P["neck_base"] + V(0, .04, .02), P["chest_top"] + V(0, .02, .03), P["ribs_high"], P["ribs_low"], P["waist"], P["pelvis"], V(0, .12, .9), V(0, .2, .62)]
CLOAK_R = [.09, .2, .215, .21, .2, .235, .3, .36]
rows, cols = 30, 30
verts = []; faces = []
def axis_at(v):
    t = v * (len(CLOAK_AXIS) - 1)
    i = min(int(t), len(CLOAK_AXIS) - 2)
    f = t - i
    a, b = CLOAK_AXIS[i], CLOAK_AXIS[i + 1]
    return a.lerp(b, f), (b - a).normalized(), CLOAK_R[i] * (1 - f) + CLOAK_R[i + 1] * f
cut = [int(rows * random.uniform(.62, 1.0)) for _ in range(cols)]
for c in range(cols):   # рваные края: длинные полосы и короткие лохмотья
    if random.random() < .25:
        cut[c] = int(rows * random.uniform(.35, .6))
grid = {}
for r in range(rows + 1):
    v = r / rows
    q, axis, rad = axis_at(v)
    back = Vector((0, abs(axis.z), -axis.y if axis.y < 0 else axis.y * .2)).normalized()
    side = Vector((1, 0, 0))
    span = math.radians(78 + 40 * v)          # сверху уже, к подолу шире
    for c in range(cols + 1):
        u = c / cols * 2 - 1
        th = u * span
        wob = noise.noise(V(u * 3, v * 5, 0.3)) * .025
        p = q + (back * math.cos(th) + side * math.sin(th)) * (rad + .035 + wob + .04 * v * v)
        p.z -= .03 * math.sin(abs(u) * math.pi) * v      # провисание
        grid[(r, c)] = len(verts)
        verts.append(p)
for r in range(rows):
    for c in range(cols):
        if r >= min(cut[c], cut[min(c + 1, cols - 1)]):
            continue
        if 5 < r < rows - 3 and random.random() < .035:   # дыры
            continue
        faces.append((grid[(r, c)], grid[(r, c + 1)], grid[(r + 1, c + 1)], grid[(r + 1, c)]))
cm = bpy.data.meshes.new("Cloak")
cm.from_pydata(verts, [], faces)
cloak = bpy.data.objects.new("Cloak", cm)
scene.collection.objects.link(cloak)
bpy.context.view_layer.objects.active = cloak
cloak.select_set(True)
solid = cloak.modifiers.new("Solid", "SOLIDIFY")
solid.thickness = .012
bpy.ops.object.modifier_apply(modifier="Solid")
for poly in cm.polygons:
    poly.use_smooth = True

# ---------------------------------------------------------------- цвет в вершинах
def srgb(c):
    return tuple((x / 12.92 if x <= .04045 else ((x + .055) / 1.055) ** 2.4) for x in c)

def paint(obj, fn):
    me = obj.data
    if "Col" not in me.color_attributes:
        me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    col = me.color_attributes["Col"]
    mw = obj.matrix_world
    for poly in me.polygons:
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            p = mw @ me.vertices[vi].co
            c = fn(p)
            col.data[li].color = (*srgb(c), 1.0)
    me.color_attributes.active_color = col

def mixc(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))

SKIN = (.5, .53, .47)       # бледная, землисто-зелёная
BRUISE = (.33, .38, .42)     # синюшные пятна утопленника
DARK = (.17, .19, .21)
def skin_color(p):
    c = mixc(SKIN, BRUISE, noise.noise(p * 4.0) * .9 + .25)
    # вены
    vein = abs(noise.noise(p * 14.0 + V(3, 1, 7)))
    if vein < .05:
        c = mixc(c, (.28, .33, .42), (1 - vein / .05) * .7)
    # конечности темнеют к кончикам (кисти, стопы), когти чёрные
    if p.z < .85:
        if abs(p.x) > .3:   # кисти
            c = mixc(c, DARK, (.85 - p.z) / .45)
            if p.z < .36:
                c = mixc(c, (.03, .03, .03), (.36 - p.z) / .08)
        else:               # стопы
            c = mixc(c, DARK, (.5 - p.z) / .45)
            if p.y < -.24:
                c = mixc(c, (.03, .03, .03), 1)
    # рот и глазницы
    if p.y < -.86 and 1.93 < p.z < 2.09 and abs(p.x) < .045:
        c = mixc(c, (.09, .02, .02), .9)
    for e in eye_pos.values():
        k = (p - e).length
        if k < .04:
            c = mixc(c, (.02, .02, .02), 1 - k / .04)
    return c
paint(body, skin_color)
for o in vert_parts:
    paint(o, lambda p: mixc(SKIN, (.8, .8, .74), .5))
for o in teeth:
    paint(o, lambda p: (.72, .66, .5))
for o in eyes:
    paint(o, lambda p: (1.0, .9, .62))
OIL = (.36, .33, .17)        # выцветший, почерневший жёлтый плащ
def cloak_color(p):
    c = mixc(OIL, (.12, .12, .09), noise.noise(p * 3.0) * .8 + .3)
    c = mixc(c, (.05, .05, .04), max(0.0, (1.0 - p.z) / .5))   # мокрый подол
    streak = abs(noise.noise(V(p.x * 18, p.y * 18, p.z * 2)))
    if streak < .06:
        c = mixc(c, (.5, .46, .26), .35)
    return c
paint(cloak, cloak_color)

# ---------------------------------------------------------------- материалы (Godot переопределит, но glb должен быть цельным)
def material(name, rough, emit=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = rough
    if emit:
        nt.links.new(attr.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emit
    return m
M_SKIN = material("HunterSkin", .3)
M_CLOAK = material("HunterCloak", .55)
M_TEETH = material("HunterTeeth", .45)
M_EYE = material("HunterEye", .2, 6.0)

def join(objs, name, mat):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
        o.data.materials.clear()
        o.data.materials.append(mat)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    o.data.name = name
    return o
body = join([body] + vert_parts, "HunterBody", M_SKIN)
cloak = join([cloak], "HunterCloak", M_CLOAK)
teeth_obj = join(teeth, "HunterTeeth", M_TEETH)
eyes_obj = join(eyes, "HunterEyes", M_EYE)
for o in (body, teeth_obj, eyes_obj, cloak):
    for poly in o.data.polygons:
        poly.use_smooth = True

# ---------------------------------------------------------------- риг
BONES = [
    # name, head, tail, parent, roll_up (True — ось Z кости смотрит вверх, иначе вперёд)
    ("hips", P["pelvis"], P["waist"], None, False),
    ("spine1", P["waist"], P["ribs_low"], "hips", False),
    ("spine2", P["ribs_low"], P["ribs_high"], "spine1", False),
    ("chest", P["ribs_high"], P["chest_top"], "spine2", False),
    ("neck", P["chest_top"], P["neck_mid"], "chest", True),
    ("head", P["neck_mid"], P["face"], "neck", True),
    ("jaw", P["jaw_root"], P["jaw_tip"], "head", True),
]
for L, s in (("L", 1), ("R", -1)):
    BONES += [
        ("shoulder." + L, P["chest_top"] + V(.05 * s, 0, 0), P["shoulder." + L], "chest", False),
        ("upperarm." + L, P["shoulder." + L], P["elbow." + L], "shoulder." + L, False),
        ("forearm." + L, P["elbow." + L], P["wrist." + L], "upperarm." + L, False),
        ("hand." + L, P["wrist." + L], P["palm." + L], "forearm." + L, False),
    ]
    for i in range(4):
        BONES += [("finger%d.%s" % (i, L), P["palm." + L], P["fk%d.%s" % (i, L)], "hand." + L, False),
                  ("finger%db.%s" % (i, L), P["fk%d.%s" % (i, L)], P["ft%d.%s" % (i, L)], "finger%d.%s" % (i, L), False)]
    BONES += [("thumb." + L, P["palm." + L], P["tht." + L], "hand." + L, False),
              ("thigh." + L, P["hip." + L], P["knee." + L], "hips", False),
              ("shin." + L, P["knee." + L], P["ankle." + L], "thigh." + L, False),
              ("foot." + L, P["ankle." + L], P["ball." + L], "shin." + L, True),
              ("toes." + L, P["ball." + L], V(P["ball." + L].x, -.31, .025), "foot." + L, True)]
# плащ: две «юбки» сзади, чтобы развевался при беге
BONES += [("cape", P["pelvis"] + V(0, .25, .1), V(0, .38, .7), "hips", False)]

arm_data = bpy.data.armatures.new("HunterRig")
rig = bpy.data.objects.new("HunterRig", arm_data)
scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
for name, h, t, parent, up in BONES:
    b = arm_data.edit_bones.new(name)
    b.head = h
    b.tail = t
    b.align_roll(Vector((0, 0, 1)) if up else Vector((0, -1, 0)))
    if parent:
        b.parent = arm_data.edit_bones[parent]
        b.use_connect = (parent and (arm_data.edit_bones[parent].tail - h).length < 1e-4)
arm_data.edit_bones["cape"].use_deform = True
bpy.ops.object.mode_set(mode="OBJECT")

def skin_to_rig(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    # страховка: вершины без весов — к ближайшей кости
    groups = {g.name: g for g in obj.vertex_groups}
    segs = [(n, h, t) for n, h, t, _, _ in BONES]
    fixed = 0
    for v in obj.data.vertices:
        if sum(g.weight for g in v.groups) > 1e-3:
            continue
        p = obj.matrix_world @ v.co
        best = None
        for n, h, t in segs:
            ab = t - h
            q = h + ab * max(0, min(1, (p - h).dot(ab) / ab.length_squared))
            d = (p - q).length
            if best is None or d < best[0]:
                best = (d, n)
        if best[1] not in groups:
            groups[best[1]] = obj.vertex_groups.new(name=best[1])
        groups[best[1]].add([v.index], 1.0, "REPLACE")
        fixed += 1
    print("weights", obj.name, "fallback verts:", fixed)

def rigid_to(obj, bone):
    """Мелкие жёсткие детали (зубы, глаза) — целиком к одной кости."""
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_NAME")
    for g in list(obj.vertex_groups):
        obj.vertex_groups.remove(g)
    g = obj.vertex_groups.new(name=bone)
    g.add([v.index for v in obj.data.vertices], 1.0, "REPLACE")

skin_to_rig(body)
skin_to_rig(cloak)
# зубы: нижние к челюсти, верхние к голове
bpy.ops.object.select_all(action="DESELECT")
rigid_to(eyes_obj, "head")
bpy.ops.object.select_all(action="DESELECT")
teeth_obj.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type="ARMATURE_NAME")
for g in list(teeth_obj.vertex_groups):
    teeth_obj.vertex_groups.remove(g)
gh = teeth_obj.vertex_groups.new(name="head")
gj = teeth_obj.vertex_groups.new(name="jaw")
for v in teeth_obj.data.vertices:
    p = teeth_obj.matrix_world @ v.co
    (gj if p.z < 2.03 else gh).add([v.index], 1.0, "REPLACE")
# челюсть в теле: нижняя часть морды целиком к jaw
jg = body.vertex_groups.get("jaw") or body.vertex_groups.new(name="jaw")
hg = body.vertex_groups.get("head")
for v in body.data.vertices:
    p = body.matrix_world @ v.co
    if p.y < -.78 and p.z < 2.06 and abs(p.x) < .07 and p.z > 1.88:
        for g in body.vertex_groups:
            g.remove([v.index])
        jg.add([v.index], 1.0, "REPLACE")

# ---------------------------------------------------------------- анимации
pb = rig.pose.bones
for b in pb:
    b.rotation_mode = "XYZ"
SIDE = {"L": 1, "R": -1}

LIMBS = ("upperarm", "forearm", "hand", "finger", "thumb", "thigh", "shin")

def mirror(rot, name):
    """Значения задаются для левой стороны; правая — зеркально по Y и Z.
    Соглашение для анимации: +X у конечностей — мах вперёд (у висящих костей локальная X смотрит назад,
    — проверено рендером), у позвоночника +X — наклон вперёд, у шеи/головы/челюсти +X — вверх."""
    x, y, z = rot
    if name.endswith(".R"):
        return (x, -y, -z)
    return (x, y, z)

def key_pose(frame, pose, loc=None):
    for b in pb:
        r = pose.get(b.name, (0, 0, 0))
        b.rotation_euler = Euler(mirror(r, b.name), "XYZ")
        b.keyframe_insert("rotation_euler", frame=frame)
        b.location = loc.get(b.name, (0, 0, 0)) if loc else (0, 0, 0)
        b.keyframe_insert("location", frame=frame)

def make_action(name, frames, sampler, step=1, cyclic=True):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = act
    for f in range(0, frames + 1, step):
        t = f / frames
        pose, loc = sampler(t)
        key_pose(f + 1, pose, loc)
    for fc in act.fcurves:
        for k in fc.keyframe_points:
            k.interpolation = "BEZIER"
    act.frame_range = (1, frames + 1)
    rig.animation_data.action = None
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 1, act)
    track.mute = True
    return act

D = math.radians
S = math.sin
C = math.cos
TAU = math.tau

def fingers(curl, spread=0.0, twitch=0.0, t=0.0):
    out = {}
    for L in ("L", "R"):
        for i in range(4):
            tw = twitch * S(TAU * (t * 3 + i * .27 + (0.5 if L == "R" else 0)))
            out["finger%d.%s" % (i, L)] = (D(curl * 30 + tw * 12), 0, D((i - 1.5) * spread))
            out["finger%db.%s" % (i, L)] = (D(curl * 45 + tw * 20), 0, 0)
        out["thumb." + L] = (D(curl * 25), 0, 0)
    return out

def base(**over):
    pose = {
        "hips": (0, 0, 0), "spine1": (D(4), 0, 0), "spine2": (D(6), 0, 0), "chest": (D(6), 0, 0),
        "neck": (D(9), 0, 0), "head": (D(6), 0, 0), "jaw": (D(-6), 0, 0),
    }
    for L in ("L", "R"):
        pose["shoulder." + L] = (0, 0, D(-4))
        pose["upperarm." + L] = (D(18), 0, D(4))      # компенсирует сутулость: руки висят отвесно
        pose["forearm." + L] = (D(10), 0, 0)
        pose["hand." + L] = (D(8), 0, 0)
        pose["thigh." + L] = (D(-6), 0, 0)
        pose["shin." + L] = (D(-6), 0, 0)
        pose["foot." + L] = (D(4), 0, 0)
    pose.update(fingers(.4))
    pose.update(over)
    return pose

def add(pose, name, rot):
    a = pose.get(name, (0, 0, 0))
    pose[name] = (a[0] + rot[0], a[1] + rot[1], a[2] + rot[2])

# idle: тяжёлое дыхание, голова покачивается, пальцы подрагивают
def idle(t):
    p = base()
    br = S(TAU * t * 2)
    add(p, "chest", (D(2.5 * br), 0, 0))
    add(p, "spine2", (D(1.5 * br), 0, 0))
    add(p, "neck", (D(-2 * br), D(3 * S(TAU * t)), 0))
    add(p, "head", (D(3 * S(TAU * t + 1)), D(6 * S(TAU * t)), D(4 * S(TAU * t * 2 + .5))))
    add(p, "jaw", (D(-6 - 6 * max(0, br)), 0, 0))
    for L in ("L", "R"):
        add(p, "upperarm." + L, (D(3 * S(TAU * t + (0 if L == "L" else 2))), 0, 0))
        add(p, "forearm." + L, (D(2 * S(TAU * t * 2)), 0, 0))
    p.update(fingers(.45, 3, .35, t))
    return p, {"hips": (0, -.012 * (1 - br) * .5, 0)}

# stalk: медленная крадущаяся походка, голова низко и неподвижно, руки волочатся
def gait(t, run):
    p = base()
    ph = TAU * t
    stride = 30 if run else 22
    lift = 50 if run else 38
    for L, off in (("L", 0.0), ("R", math.pi)):
        a = ph + off
        if run and L == "R":
            a += .35 * S(ph)          # хромающий, рваный ритм
        add(p, "thigh." + L, (D(stride * S(a)), 0, 0))
        add(p, "shin." + L, (D(-lift * max(0, S(a + 1.6)) - 6), 0, 0))
        add(p, "foot." + L, (D(18 * S(a + .8)), 0, 0))
        arm = -S(a) * (30 if run else 14)
        add(p, "upperarm." + L, (D(arm + (18 if run else 8)), 0, D(8 if run else 2)))
        add(p, "forearm." + L, (D((30 if run else 12) + (20 if run else 6) * S(a + .9)), 0, 0))
        add(p, "hand." + L, (D(15 * S(a + 1.5)), 0, 0))
    lean = 26 if run else 10
    add(p, "spine1", (D(lean * .35), D(4 * S(ph)), 0))
    add(p, "spine2", (D(lean * .35), D(-3 * S(ph)), 0))
    add(p, "chest", (D(lean * .3), D(6 * S(ph)), D(4 * S(ph))))
    # голову держит ровно (стабилизация), на бегу — рывками
    add(p, "neck", (D(-lean * .6), D(-5 * S(ph)), 0))
    jerk = (D(10 * S(ph * 2 + .3) * S(ph * 3)) if run else 0)
    add(p, "head", (D(-lean * .4) + jerk, D(-3 * S(ph)), D(8 * S(ph * 2)) if run else 0))
    add(p, "jaw", (D(-18 - 10 * max(0, S(ph * 2))) if run else D(-4), 0, 0))
    add(p, "cape", (D(-35 - 10 * S(ph * 2)) if run else D(-6 * S(ph * 2)), 0, D(6 * S(ph))))
    p.update(fingers(.25 if run else .5, 6 if run else 2, .2, t))
    bob = (.07 if run else .03) * abs(C(ph))
    return p, {"hips": (0, -bob, 0)}

# search: замирает, принюхивается, голова дёргается по-птичьи
def search(t):
    p = base()
    add(p, "spine2", (D(8), 0, 0))
    add(p, "chest", (D(8), D(10 * S(TAU * t)), 0))
    # рывки головы: ступенчатые повороты
    steps = [(-28, 18), (22, -14), (-8, 30), (30, 10), (0, -22), (-28, 18)]
    k = t * (len(steps) - 1)
    i = int(k); f = k - i
    f = f ** 6 if f < .5 else 1 - (1 - f) ** 6   # резко, затем замирает
    f = min(1.0, f * 1.0)
    a, b = steps[i], steps[min(i + 1, len(steps) - 1)]
    yaw = a[0] + (b[0] - a[0]) * f
    tilt = a[1] + (b[1] - a[1]) * f
    sniff = S(TAU * t * 14) * max(0, S(TAU * t * 2)) * 4
    add(p, "neck", (D(-14 + sniff), D(yaw * .3), 0))
    add(p, "head", (D(-6 + sniff * 1.5), D(tilt), D(yaw)))
    add(p, "jaw", (D(-3 - 4 * abs(sniff) / 4), 0, 0))
    for L in ("L", "R"):
        add(p, "upperarm." + L, (D(14), 0, D(6)))
        add(p, "forearm." + L, (D(20), 0, 0))
    p.update(fingers(.7, 8, .6, t))
    return p, {"hips": (0, -.03, 0)}

# grab: выпрямляется, руки назад, затем бросок и хват
def grab(t):
    p = base()
    def seg(t0, t1):
        return max(0.0, min(1.0, (t - t0) / (t1 - t0)))
    rear = seg(0, .3) - seg(.3, .45)
    lunge = seg(.3, .45) - seg(.7, 1.0)
    close = seg(.42, .52) - seg(.8, 1.0)
    add(p, "spine1", (D(-14 * rear + 20 * lunge), 0, 0))
    add(p, "spine2", (D(-12 * rear + 16 * lunge), 0, 0))
    add(p, "chest", (D(-10 * rear + 14 * lunge), 0, 0))
    add(p, "neck", (D(14 * rear - 10 * lunge), 0, 0))
    add(p, "head", (D(18 * rear + 6 * lunge), 0, 0))
    add(p, "jaw", (D(-38 * max(rear, lunge)), 0, 0))
    for L in ("L", "R"):
        add(p, "shoulder." + L, (D(-10 * rear + 20 * lunge), 0, D(14 * rear)))
        add(p, "upperarm." + L, (D(-40 * rear + 62 * lunge), 0, D(38 * rear + 10 * lunge)))
        add(p, "forearm." + L, (D(30 * rear + 10 * lunge + 40 * close), 0, 0))
        add(p, "thigh." + L, (D(18 * lunge if L == "L" else -14 * lunge), 0, 0))
        add(p, "shin." + L, (D(-25 * lunge), 0, 0))
    p.update(fingers(.1 - .3 * rear + 1.3 * close, 14 * rear, 0, t))
    return p, {"hips": (0, .06 * rear - .1 * lunge, -.25 * lunge)}

# door_wait: прижался к двери, слушает, одна рука скребёт
def door_wait(t):
    p = base()
    add(p, "spine1", (D(6), 0, 0))
    add(p, "chest", (D(6), D(-6), 0))
    add(p, "neck", (D(-4), D(-10), D(-14)))
    add(p, "head", (D(4 * S(TAU * t)), D(-24 + 4 * S(TAU * t * 2)), D(-12)))
    add(p, "jaw", (D(-10 - 4 * S(TAU * t * 2)), 0, 0))
    scratch = S(TAU * t * 6)
    add(p, "upperarm.L", (D(42 + 4 * scratch), 0, D(8)))
    add(p, "forearm.L", (D(55 + 8 * scratch), 0, 0))
    add(p, "hand.L", (D(-20 + 10 * scratch), 0, 0))
    p.update(fingers(.5, 4, .2, t))
    for i in range(4):
        add(p, "finger%d.L" % i, (D(20 * max(0, S(TAU * t * 6 + i * .6))), 0, 0))
        add(p, "finger%db.L" % i, (D(30 * max(0, S(TAU * t * 6 + i * .6))), 0, 0))
    add(p, "upperarm.R", (D(4), 0, D(2)))
    br = S(TAU * t * 2)
    add(p, "chest", (D(2 * br), 0, 0))
    return p, {"hips": (0, -.02, -.04)}

make_action("idle", 90, idle, 2)
make_action("stalk", 40, lambda t: gait(t, False), 1)
make_action("lurch", 22, lambda t: gait(t, True), 1)
make_action("search", 120, search, 1)
make_action("grab", 36, grab, 1, False)
make_action("door_wait", 120, door_wait, 2)

# поза покоя по умолчанию — idle
rig.animation_data.action = bpy.data.actions["idle"]
scene.frame_set(1)

bpy.ops.wm.save_as_mainfile(filepath=BLEND)
print("Saved", BLEND)

# ---------------------------------------------------------------- экспорт
for t in rig.animation_data.nla_tracks:
    t.mute = False
rig.animation_data.action = None
bpy.ops.object.select_all(action="DESELECT")
for o in (rig, body, cloak, teeth_obj, eyes_obj):
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=GLB, export_format="GLB", use_selection=True,
    export_animations=True, export_animation_mode="ACTIONS", export_force_sampling=True,
    export_skins=True, export_def_bones=False,
    export_attributes=False, export_vertex_color="ACTIVE",
    export_yup=True, export_apply=False)
print("Exported", GLB, os.path.getsize(GLB))

# ---------------------------------------------------------------- превью (Cycles на CPU)
if RENDER:
    os.makedirs(RENDER, exist_ok=True)
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.render.resolution_x = 480
    scene.render.resolution_y = 600
    world = bpy.data.worlds.new("W"); scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (.02, .025, .03, 1)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    scene.collection.objects.link(cam); scene.camera = cam
    for (name, loc, energy, color) in [("Key", (-2.5, -3, 3.5), 450, (1, .9, .8)), ("Rim", (2, 2.5, 3), 600, (.6, .75, 1)), ("Fill", (3, -2, 1.5), 120, (.8, .9, 1))]:
        L = bpy.data.objects.new(name, bpy.data.lights.new(name, "AREA"))
        L.data.energy = energy; L.data.color = color; L.data.size = 1.5
        L.location = loc
        L.rotation_euler = (Vector((0, 0, 1.3)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(L)
    shots = [("idle", 1, (-2.6, -3.2, 1.7)), ("stalk", 10, (-3.4, -1.6, 1.5)), ("lurch", 6, (3.2, -2.4, 1.6)),
             ("search", 30, (-1.2, -3.6, 2.0)), ("grab", 16, (-1.6, -3.4, 1.8)), ("door_wait", 30, (2.8, -2.6, 1.7)),
             ("face", 1, (-.55, -2.05, 2.25)), ("side", 1, (-3.6, -.3, 1.4)), ("back", 1, (1.6, 3.2, 2.0))]
    only = args[args.index("--only") + 1].split(",") if "--only" in args else []
    for t in rig.animation_data.nla_tracks:
        t.mute = True
    for name, frame, cam_at in shots:
        if only and name not in only:
            continue
        rig.animation_data.action = bpy.data.actions[name if name in bpy.data.actions else "idle"]
        scene.frame_set(frame)
        cam.location = cam_at
        look = Vector((0, -.9, 2.1)) if name == "face" else Vector((0, -.35, 1.35))
        cam.rotation_euler = (look - Vector(cam_at)).to_track_quat("-Z", "Y").to_euler()
        cam.data.lens = 38
        scene.render.filepath = os.path.join(RENDER, "hunter_%s.png" % name)
        bpy.ops.render.render(write_still=True)
        print("Rendered", scene.render.filepath)
