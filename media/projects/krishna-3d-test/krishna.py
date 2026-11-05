"""Bal Krishna, seated in a meadow: a cartoon character built entirely in code with Blender (bpy), CPU Cycles,
toon shading and Freestyle outlines. A feasibility test for 3D cartoon reels on this machine (no GPU).

usage: $MEDIA_BLENDER_PY krishna.py -- <out_dir> still <frame>      one PNG (frame number, 1-120)
       $MEDIA_BLENDER_PY krishna.py -- <out_dir> anim [first last]  PNG sequence, 12 fps "on twos", 10 s = 120 frames
Options via env: KR_W/KR_H (default 720x1280), KR_SAMPLES (default 12).

Traditional iconography only (blue skin, peacock feather, tilak, yellow dhoti, bead necklaces); no reference image used.
"""
import math
import os
import random
import sys

import bpy  # noqa: I001  (bpy must be imported before bmesh in the standalone module)
import bmesh
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT, MODE = argv[0], argv[1]
os.makedirs(OUT, exist_ok=True)
W, H = int(os.environ.get("KR_W", 720)), int(os.environ.get("KR_H", 1280))
FPS, FRAMES = 12, 120
rng = random.Random(7)


def lin(hexs):
    """sRGB hex -> linear RGBA"""
    c = [int(hexs[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c) + (1.0,)


# ---------------------------------------------------------------- scene reset
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
sc = bpy.context.scene
CHAR = bpy.data.collections.new("character")
ENV = bpy.data.collections.new("environment")
sc.collection.children.link(CHAR)
sc.collection.children.link(ENV)

# ---------------------------------------------------------------- shared meshes


def _mesh(name, build):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    build(bm)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    return me


SPHERE = _mesh("sphere", lambda bm: bmesh.ops.create_uvsphere(bm, u_segments=40, v_segments=20, radius=1))
SPHERE_LO = _mesh("sphere_lo", lambda bm: bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=8, radius=1))
CYL = _mesh("cyl", lambda bm: bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=20, radius1=1, radius2=1, depth=2))


def _torus(bm, R=1.0, r=0.2, nu=32, nv=12):
    verts = []
    for i in range(nu):
        a = 2 * math.pi * i / nu
        ring = []
        for j in range(nv):
            b = 2 * math.pi * j / nv
            ring.append(bm.verts.new(((R + r * math.cos(b)) * math.cos(a), (R + r * math.cos(b)) * math.sin(a), r * math.sin(b))))
        verts.append(ring)
    for i in range(nu):
        for j in range(nv):
            bm.faces.new((verts[i][j], verts[(i + 1) % nu][j], verts[(i + 1) % nu][(j + 1) % nv], verts[i][(j + 1) % nv]))


TORUS = _mesh("torus", _torus)

# ---------------------------------------------------------------- materials (toon: one crisp shadow step + ambient)
MATS = {}


def mat(name, hexs, amb=0.32, gloss=0.0, emit=None):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    col = lin(hexs)
    if emit is not None:
        e = nt.nodes.new("ShaderNodeEmission")
        e.inputs[0].default_value = col
        e.inputs[1].default_value = emit
        nt.links.new(e.outputs[0], out.inputs[0])
    else:
        toon = nt.nodes.new("ShaderNodeBsdfToon")
        toon.inputs["Color"].default_value = col
        toon.inputs["Size"].default_value = 0.62
        toon.inputs["Smooth"].default_value = 0.04
        e = nt.nodes.new("ShaderNodeEmission")
        e.inputs[0].default_value = col
        e.inputs[1].default_value = amb
        add = nt.nodes.new("ShaderNodeAddShader")
        nt.links.new(toon.outputs[0], add.inputs[0])
        nt.links.new(e.outputs[0], add.inputs[1])
        last = add
        if gloss:
            g = nt.nodes.new("ShaderNodeBsdfToon")
            g.component = "GLOSSY"
            g.inputs["Color"].default_value = (gloss, gloss, gloss, 1)
            g.inputs["Size"].default_value = 0.18
            g.inputs["Smooth"].default_value = 0.05
            add2 = nt.nodes.new("ShaderNodeAddShader")
            nt.links.new(add.outputs[0], add2.inputs[0])
            nt.links.new(g.outputs[0], add2.inputs[1])
            last = add2
        nt.links.new(last.outputs[0], out.inputs[0])
    MATS[name] = m
    return m


SKIN = mat("skin", "#7d95d8", amb=0.36)
SKIN_D = mat("skin_dark", "#5d73bd", amb=0.36)
DHOTI = mat("dhoti", "#f3b52c", amb=0.36)
DHOTI_D = mat("dhoti_fold", "#d48f1f", amb=0.36)
HAIR = mat("hair", "#1c1e2c", amb=0.55)
WHITE = mat("eyewhite", "#fbf6ee", amb=0.6)
IRIS = mat("iris", "#6e3f20", amb=0.45)
PUPIL = mat("pupil", "#1a0e08", amb=0.5)
SHINE = mat("shine", "#ffffff", emit=2.2)
LASH = mat("lash", "#120c0c", amb=0.5)
RED = mat("tilak", "#e2412b", amb=0.45)
LIPS = mat("lips", "#c9554c", amb=0.4)
GOLD = mat("gold", "#d8a23c", amb=0.32, gloss=0.35)
BEAD = mat("bead", "#3b2418", amb=0.32, gloss=0.18)
F_GREEN = mat("f_green", "#2f8a3c", amb=0.4)
F_GOLD = mat("f_gold", "#c9952b", amb=0.4)
F_TEAL = mat("f_teal", "#17a8a3", amb=0.45)
F_BLUE = mat("f_blue", "#1d3fae", amb=0.45)
F_NAVY = mat("f_navy", "#0a1240", amb=0.5)
GROUND = mat("ground", "#69bb4b", amb=0.38)
GRASS1 = mat("grass1", "#4f9e3c", amb=0.4)
GRASS2 = mat("grass2", "#7cc556", amb=0.4)
LEAF1 = mat("leaf1", "#3b8a39", amb=0.38)
LEAF2 = mat("leaf2", "#62ad46", amb=0.38)
FAR = mat("far", "#5fa98a", amb=0.6)
TRUNK = mat("trunk", "#6b4a2b", amb=0.35)
CLOUD = mat("cloud", "#ffffff", amb=0.85)
FL_Y = mat("fl_y", "#f6d63c", amb=0.5)
FL_P = mat("fl_p", "#f18ab6", amb=0.5)
FL_W = mat("fl_w", "#fbf7f0", amb=0.55)
PETAL = mat("petal", "#f59a3a", amb=0.55)

# ---------------------------------------------------------------- object helpers


def obj(name, mesh, m, matrix, coll=CHAR):
    o = bpy.data.objects.new(name, mesh)
    o.data = mesh
    o.matrix_world = matrix
    if not o.material_slots:
        o.data.materials.clear() if False else None
    o.active_material = None
    coll.objects.link(o)
    # materials live on the object, so shared meshes can carry different colours
    o.material_slots and None
    if not o.data.materials:
        o.data.materials.append(None)
    o.material_slots[0].link = "OBJECT"
    o.material_slots[0].material = m
    return o


def frame_from(z, y_hint):
    z = Vector(z).normalized()
    y = Vector(y_hint)
    y = (y - z * y.dot(z)).normalized()
    x = y.cross(z).normalized()
    return Matrix((x, y, z)).transposed()


def ell(name, loc, scale, m, rot=None, coll=CHAR, mesh=SPHERE):
    R = rot if rot is not None else Matrix.Identity(3)
    return obj(name, mesh, m, Matrix.Translation(loc) @ R.to_4x4() @ Matrix.Diagonal((*scale, 1)), coll)


def limb(name, p0, p1, r, m, coll=CHAR, extra=1.25):
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    R = frame_from(d, (0, -1, 0))
    return ell(name, (p0 + p1) / 2, (r, r, d.length / 2 + r * (extra - 1)), m, R, coll)


def ring(name, center, axis, R_, r, m):
    Rm = frame_from(axis, (0, -1, 0))
    return obj(name, TORUS, m, Matrix.Translation(center) @ Rm.to_4x4() @ Matrix.Diagonal((R_, R_, R_, 1)) @ Matrix.Diagonal((1, 1, r / R_ / 0.2, 1)), CHAR)


def parent(child, par):
    mw = child.matrix_world.copy()
    child.parent = par
    child.matrix_world = mw


def empty(name, loc, rot=None, coll=CHAR):
    e = bpy.data.objects.new(name, None)
    e.matrix_world = Matrix.Translation(loc) @ (rot.to_4x4() if rot is not None else Matrix.Identity(4))
    coll.objects.link(e)
    return e


# ---------------------------------------------------------------- head (one deformed sphere: narrower jaw, no seams)
HC, HR = Vector((0, 0, 1.30)), 0.30
JX, JY = 0.24, 0.10   # jaw narrowing in x and y towards the chin


def jaw(zl):
    t = max(0.0, -zl) ** 1.5
    return 1 - JX * t, 1 - JY * t


head_me = SPHERE.copy()
for v in head_me.vertices:
    fx, fy = jaw(v.co.z)
    v.co.x *= fx
    v.co.y *= fy
head_root = empty("head_root", (0, 0.0, 1.04))
parts_head = []
head = ell("head", HC, (HR, HR, HR), SKIN, mesh=head_me)
parts_head.append(head)


def surf(x, z, out=0.0):
    """point on the deformed head surface (front), with its outward normal"""
    zl = (z - HC.z) / HR
    fx, fy = jaw(zl)
    xl = x / (HR * fx)
    yl = -math.sqrt(max(0.0, 1 - xl * xl - zl * zl))
    n = Vector((xl / fx, yl / fy, zl)).normalized()
    p = Vector((x, HC.y + yl * HR * fy, z)) + n * out
    return p, n


def decal(name, x, z, scale, m, out, roll=0.0):
    p, n = surf(x, z, out)
    R = frame_from(Vector((0, 0, 1)) - n * n.z, -n)   # local y faces the viewer, local z points up the face
    R = R @ Matrix.Rotation(roll, 3, "Y")
    o = ell(name, p, (scale[0], scale[1], scale[2]), m, R)
    return o, p, R


# eyes: white, iris, pupil, shine, upper lash, brow; each eye under its own empty so it can blink
eye_roots = []
for side in (-1, 1):
    ex, ez = 0.112 * side, 1.272
    p, n = surf(ex, ez, 0.0)
    R = frame_from(Vector((0, 0, 1)) - n * n.z, -n)
    root = empty(f"eye_root{side}", p, R)
    eye_roots.append(root)
    pieces = [decal(f"eyewhite{side}", ex, ez, (0.080, 0.014, 0.090), WHITE, 0.002)[0],
              decal(f"iris{side}", ex - 0.006 * side, ez - 0.006, (0.058, 0.012, 0.070), IRIS, 0.009)[0],
              decal(f"pupil{side}", ex - 0.006 * side, ez - 0.010, (0.028, 0.010, 0.036), PUPIL, 0.015)[0],
              decal(f"shine{side}", ex + 0.016 * side, ez + 0.026, (0.016, 0.008, 0.020), SHINE, 0.020)[0],
              decal(f"shine_s{side}", ex - 0.022 * side, ez - 0.034, (0.008, 0.006, 0.010), SHINE, 0.020)[0],
              decal(f"lash{side}", ex + 0.004 * side, ez + 0.078, (0.092, 0.012, 0.016), LASH, 0.010, roll=0.10 * side)[0]]
    for pc in pieces:
        parent(pc, root)
    parts_head.append(root)
    parts_head.append(decal(f"brow{side}", 0.118 * side, 1.415, (0.050, 0.008, 0.008), LASH, 0.004, roll=-0.14 * side)[0])

parts_head += [decal("nose", 0.0, 1.195, (0.016, 0.014, 0.013), SKIN_D, 0.004)[0],
               decal("mouth", 0.0, 1.118, (0.030, 0.008, 0.010), LIPS, 0.002)[0],
               decal("tilak", 0.0, 1.452, (0.013, 0.008, 0.040), RED, 0.004)[0],
               decal("tilak_dot", 0.0, 1.405, (0.010, 0.008, 0.010), RED, 0.004)[0]]
for side in (-1, 1):
    parts_head.append(ell(f"ear{side}", (0.292 * side, 0.02, 1.27), (0.045, 0.03, 0.07), SKIN))
    parts_head.append(ell(f"earring{side}", (0.300 * side, -0.005, 1.185), (0.022, 0.022, 0.022), GOLD))
    parts_head.append(ell(f"eardrop{side}", (0.300 * side, -0.005, 1.150), (0.013, 0.013, 0.022), RED))

# hair: clumps flowing down the scalp, side locks framing the face, bangs with a gap for the tilak


def clump(name, base, normal, length, width, thick, droop=1.0):
    n = Vector(normal).normalized()
    down = Vector((0, 0, -1))
    t = (down - n * down.dot(n))
    if t.length < 1e-3:
        t = Vector((0, 1, 0))
    t = (t.normalized() * droop + n * (1 - droop) * 0.6).normalized()
    R = frame_from(t, n)
    return ell(name, Vector(base) + t * length * 0.6, (width, thick, length), HAIR, R)


cap_me = SPHERE.copy()
bm = bmesh.new()
bm.from_mesh(cap_me)
bmesh.ops.delete(bm, geom=[v for v in bm.verts if (v.co.y < -0.28 and v.co.z < 0.62) or v.co.z < -0.38 or (v.co.y < 0.1 and v.co.z < 0.0 and abs(v.co.x) < 0.8)], context="VERTS")
bm.to_mesh(cap_me)
bm.free()
hair = [ell("hair_cap", HC + Vector((0, 0.012, 0.018)), (HR * 1.045, HR * 1.045, HR * 1.045), HAIR, mesh=cap_me)]
k = 0
N = 90
for i in range(N):
    zz = 1 - 2 * (i + 0.5) / N
    rr = math.sqrt(1 - zz * zz)
    ph = math.pi * (1 + 5 ** 0.5) * i
    d = Vector((rr * math.cos(ph), rr * math.sin(ph), zz))
    face = d.y < -0.30 and d.z < 0.62
    if face or d.z < -0.45 or (d.z < 0.05 and d.y < 0.0 and abs(d.x) < 0.75):
        continue
    base = HC + d * HR * 0.97
    hair.append(clump(f"hair{k}", HC + d * HR * 1.0, d, 0.12 + rng.random() * 0.05, 0.08 + rng.random() * 0.025, 0.065, 0.85))
    k += 1
# shoulder-length curls around the back and sides
for i in range(16):
    a = math.radians(-35 + 250 * i / 15)   # from the right cheek round the back to the left cheek
    x, y = 0.30 * math.sin(a), 0.30 * math.cos(a) * 0.9 + 0.02
    if y < -0.06:
        continue
    for j, z in enumerate((1.20, 1.07)):
        n = Vector((x, y, 0)).normalized()
        R = frame_from((n.x * 0.25, n.y * 0.25, -1), n)
        hair.append(ell(f"lock{i}_{j}", (x * 1.06, y * 1.06, z), (0.075, 0.055, 0.13 - j * 0.02), HAIR, R))
# face-framing side locks
for side in (-1, 1):
    for j, (y, z) in enumerate(((-0.12, 1.32), (-0.10, 1.20), (-0.06, 1.10))):
        n = Vector((side, -0.4, 0)).normalized()
        R = frame_from((0.12 * side, -0.05, -1), n)
        hair.append(ell(f"side{side}_{j}", (0.285 * side, y, z), (0.06, 0.045, 0.12), HAIR, R))
# bangs
for x in (-0.19, -0.12, 0.12, 0.19):
    p, n = surf(x, 1.53, 0.014)
    tip_z = 1.455 if abs(x) > 0.15 else 1.475
    length = (p.z - tip_z) / 2 + 0.03
    R = frame_from((x * 0.25, -0.15, -1), n)
    hair.append(ell(f"bang{x}", (p.x, p.y, (p.z + tip_z) / 2 + 0.02), (0.055, 0.035, length + 0.04), HAIR, R))
parts_head += hair

# peacock feather, in the hair at the top right
fb = Vector((0.13, 0.07, 1.57))
fd = Vector((0.45, 0.20, 1.0)).normalized()
feather_root = empty("feather_root", fb, frame_from(fd, (0, -1, 0)))
fR = frame_from(fd, (0, -1, 0))
fparts = [limb("stem", fb, fb + fd * 0.40, 0.006, F_GOLD, extra=1.0),
          ell("vane", fb + fd * 0.33, (0.085, 0.010, 0.19), F_GREEN, fR)]
for idx, (sx, sz, m) in enumerate(((0.064, 0.080, F_GOLD), (0.050, 0.062, F_TEAL), (0.036, 0.046, F_BLUE), (0.021, 0.028, F_NAVY))):
    fparts.append(ell(f"eye_ring{idx}", fb + fd * 0.37 + Vector((0, -1, 0)) * (0.006 + 0.004 * idx), (sx, 0.008, sz), m, fR))
for i in range(14):
    a = math.radians(-70 + 140 * i / 13)
    side = 1 if i % 2 else -1
    dirb = (fR @ Vector((math.sin(a) * side, 0, math.cos(a) * 0.6 + 0.4))).normalized()
    start = fb + fd * (0.20 + 0.012 * i)
    fparts.append(limb(f"barb{i}", start, start + dirb * 0.11, 0.0045, F_GREEN if i % 3 else F_GOLD, extra=1.0))
for fp in fparts:
    parent(fp, feather_root)
parts_head.append(feather_root)

for p in parts_head:
    parent(p, head_root)

# ---------------------------------------------------------------- body
neck = ell("neck", (0, 0.015, 1.00), (0.078, 0.072, 0.09), SKIN)
torso = ell("torso", (0, 0.02, 0.70), (0.25, 0.18, 0.28), SKIN)
seat = ell("seat", (0, 0.0, 0.33), (0.36, 0.25, 0.17), DHOTI)
lap = ell("lap", (0, -0.08, 0.15), (0.50, 0.32, 0.13), DHOTI)
limb("shin_l", (-0.46, -0.08, 0.13), (0.20, -0.36, 0.13), 0.10, DHOTI)
limb("shin_r", (0.46, -0.08, 0.15), (-0.20, -0.34, 0.17), 0.095, DHOTI)
limb("pleat", (0, -0.235, 0.42), (0, -0.30, 0.25), 0.014, DHOTI_D, extra=1.0)
for i, x in enumerate((-0.26, 0.26)):
    limb(f"fold{i}", (x * 0.4, -0.27, 0.24), (x, -0.36, 0.20), 0.012, DHOTI_D, extra=1.0)
ell("sole", (0.17, -0.40, 0.25), (0.085, 0.045, 0.05), SKIN, frame_from((1, -0.3, 0.15), (0, -1, 0.3)))
for side in (-1, 1):
    sh, el, hd = Vector((0.215 * side, 0.03, 0.88)), Vector((0.35 * side, 0.02, 0.62)), Vector((0.38 * side, -0.22, 0.36))
    ell(f"shoulder{side}", sh, (0.08, 0.08, 0.08), SKIN)
    limb(f"upper{side}", sh, el, 0.07, SKIN)
    limb(f"fore{side}", el, hd, 0.06, SKIN)
    ell(f"hand{side}", hd + Vector((0, -0.02, -0.01)), (0.062, 0.055, 0.045), SKIN)
    ring(f"armband{side}", sh.lerp(el, 0.55), el - sh, 0.072, 0.015, BEAD)
    ell(f"armgem{side}", sh.lerp(el, 0.55) + Vector((0, -0.07, 0)), (0.016, 0.012, 0.02), GOLD)
    ring(f"bracelet{side}", el.lerp(hd, 0.82), hd - el, 0.062, 0.014, BEAD)

# rudraksha-style bead necklaces on the chest
TC, TR = Vector((0, 0.02, 0.70)), Vector((0.25, 0.18, 0.28))


def chest_y(x, z):
    q = 1 - (x / TR.x) ** 2 - ((z - TC.z) / TR.z) ** 2
    return TC.y - TR.y * math.sqrt(max(0.0, q))


for si, (w, zlow, ztop, br) in enumerate(((0.115, 0.80, 0.97, 0.015), (0.150, 0.62, 0.97, 0.017))):
    tmax = 1.35
    pts, prev = [], None
    steps = 400
    for s in range(steps + 1):
        t = -tmax + 2 * tmax * s / steps
        x = w * math.sin(t)
        z = zlow + (ztop - zlow) * (1 - math.cos(t)) / (1 - math.cos(tmax))
        p = Vector((x, chest_y(x, z) - br * 1.1, z))
        if prev is None or (p - prev).length >= br * 2.05:
            pts.append(p)
            prev = p
    for bi, p in enumerate(pts):
        ell(f"bead{si}_{bi}", p, (br, br, br), BEAD, mesh=SPHERE_LO)
    low = Vector((0, chest_y(0, zlow) - 0.03, zlow - 0.04))
    if si == 0:
        ell("pendant0", low, (0.018, 0.012, 0.03), BEAD)
    else:
        ell("pendant1", low + Vector((0, -0.005, -0.01)), (0.026, 0.012, 0.042), GOLD)
        ell("pendant1b", low + Vector((0, -0.016, -0.01)), (0.012, 0.008, 0.02), RED)

# ---------------------------------------------------------------- meadow, trees, sky
obj("ground", CYL, GROUND, Matrix.Translation((0, 4, -0.05)) @ Matrix.Diagonal((14, 14, 0.05, 1)), ENV)
for i, (x, y, s) in enumerate(((-5, 9, 3.2), (4.5, 10, 3.6), (0, 13, 4.0))):
    ell(f"hill{i}", (x, y, -s * 0.55), (s * 1.6, s, s), FAR, coll=ENV, mesh=SPHERE_LO)
for i in range(26):   # far tree line
    x = -9 + 18 * i / 25 + rng.uniform(-0.3, 0.3)
    ell(f"far{i}", (x, 9 + rng.uniform(-0.5, 0.8), 0.9 + rng.uniform(0, 0.6)), (0.9, 0.7, 1.0 + rng.uniform(0, 0.5)), FAR if i % 3 else LEAF1, coll=ENV, mesh=SPHERE_LO)


def tree(name, x, y, h, crown):
    obj(f"{name}_trunk", CYL, TRUNK, Matrix.Translation((x, y, h / 2)) @ Matrix.Diagonal((0.13, 0.13, h / 2, 1)), ENV)
    for i, (dx, dy, dz, r) in enumerate(crown):
        ell(f"{name}_c{i}", (x + dx, y + dy, h + dz), (r, r * 0.85, r * 0.8), LEAF1 if i % 2 else LEAF2, coll=ENV, mesh=SPHERE_LO)


tree("treeL", -1.9, 2.6, 2.6, [(0, 0, 0, 0.8), (0.7, -0.3, 0.3, 0.65), (-0.5, 0.2, 0.4, 0.7), (0.3, 0.1, 0.8, 0.6), (1.2, -0.6, 0.6, 0.5), (0.9, -0.4, 1.0, 0.45)])
tree("treeR", 2.2, 4.0, 2.4, [(0, 0, 0, 0.75), (-0.5, 0, 0.35, 0.6), (0.4, 0.2, 0.5, 0.6), (0, 0, 0.9, 0.55)])
for i in range(7):   # bushes behind the child
    x = -2.4 + 4.8 * i / 6
    ell(f"bush{i}", (x, 2.2 + rng.uniform(0, 0.6), 0.15), (0.6, 0.4, 0.45), LEAF2 if i % 2 else LEAF1, coll=ENV, mesh=SPHERE_LO)
CLOUDS = []
for c, (cx, cz) in enumerate(((-3.5, 4.6), (1.5, 5.4), (5.0, 3.9))):
    g = empty(f"cloud{c}", (cx, 16, cz), coll=ENV)
    for i in range(7):
        b = ell(f"cloud{c}_{i}", (cx + rng.uniform(-1.2, 1.2), 16 + rng.uniform(-0.3, 0.3), cz + rng.uniform(-0.2, 0.5)),
                (0.9 + rng.uniform(0, 0.6),) * 2 + (0.6 + rng.uniform(0, 0.3),), CLOUD, coll=ENV, mesh=SPHERE_LO)
        parent(b, g)
    CLOUDS.append(g)
# grass tufts and flowers (no outlines: environment collection)
for i in range(170):
    x, y = rng.uniform(-2.6, 2.6), rng.uniform(-1.4, 3.5)
    if math.hypot(x, (y + 0.05) * 1.3) < 0.62:
        continue
    for b in range(4):
        a = rng.uniform(0, 2 * math.pi)
        tilt = Vector((math.cos(a) * 0.35, math.sin(a) * 0.35, 1))
        h = rng.uniform(0.07, 0.15)
        limb(f"g{i}_{b}", (x, y, 0), Vector((x, y, 0)) + tilt.normalized() * h, 0.012, GRASS1 if (i + b) % 3 else GRASS2, coll=ENV, extra=1.0)
for i in range(34):
    x, y = rng.uniform(-2.2, 2.2), rng.uniform(-1.2, 2.0)
    if math.hypot(x, (y + 0.05) * 1.3) < 0.7:
        continue
    h = rng.uniform(0.12, 0.25)
    limb(f"stalk{i}", (x, y, 0), (x, y, h), 0.007, GRASS1, coll=ENV, extra=1.0)
    m = (FL_Y, FL_P, FL_W)[i % 3]
    for p in range(5):
        a = 2 * math.pi * p / 5
        ell(f"fl{i}_{p}", (x + 0.03 * math.cos(a), y + 0.03 * math.sin(a), h), (0.028, 0.028, 0.012), m, coll=ENV, mesh=SPHERE_LO)
    ell(f"flc{i}", (x, y, h + 0.008), (0.014, 0.014, 0.012), FL_Y if m is not FL_Y else mat("fl_c", "#e07a1f", amb=0.5), coll=ENV, mesh=SPHERE_LO)
PETALS = []
for i in range(9):
    PETALS.append(ell(f"petal{i}", (0, 0, 0), (0.03, 0.012, 0.02), PETAL if i % 2 else FL_P, coll=ENV, mesh=SPHERE_LO))

# sky: gradient for the camera, soft blue light for everything else
world = bpy.data.worlds.new("sky")
sc.world = world
world.use_nodes = True
nt = world.node_tree
nt.nodes.clear()
wo = nt.nodes.new("ShaderNodeOutputWorld")
tc = nt.nodes.new("ShaderNodeTexCoord")
sep = nt.nodes.new("ShaderNodeSeparateXYZ")
ramp = nt.nodes.new("ShaderNodeValToRGB")
ramp.color_ramp.elements[0].position, ramp.color_ramp.elements[0].color = 0.45, lin("#cfe8f8")
ramp.color_ramp.elements[1].position, ramp.color_ramp.elements[1].color = 1.0, lin("#3b8be4")
bg_cam = nt.nodes.new("ShaderNodeBackground")
bg_amb = nt.nodes.new("ShaderNodeBackground")
bg_amb.inputs[0].default_value = lin("#a9c8f0")
bg_amb.inputs[1].default_value = 0.55
lp = nt.nodes.new("ShaderNodeLightPath")
mix = nt.nodes.new("ShaderNodeMixShader")
nt.links.new(tc.outputs["Window"], sep.inputs[0])
nt.links.new(sep.outputs["Y"], ramp.inputs[0])
nt.links.new(ramp.outputs[0], bg_cam.inputs[0])
nt.links.new(lp.outputs["Is Camera Ray"], mix.inputs[0])
nt.links.new(bg_amb.outputs[0], mix.inputs[1])
nt.links.new(bg_cam.outputs[0], mix.inputs[2])
nt.links.new(mix.outputs[0], wo.inputs[0])

sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 3.2
sun.data.angle = math.radians(3)
sun.data.color = lin("#fff1dc")[:3]
L = Vector((0.45, 0.65, -0.62)).normalized()
sun.rotation_euler = Vector((0, 0, -1)).rotation_difference(L).to_euler()
ENV.objects.link(sun)

# ---------------------------------------------------------------- camera
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
cam.data.lens = 50
cam.data.sensor_fit = "VERTICAL"
cam.data.sensor_height = 36
ENV.objects.link(cam)
sc.camera = cam
target = empty("target", (0, 0, 0.92), coll=ENV)
tr = cam.constraints.new("TRACK_TO")
tr.target = target
tr.track_axis = "TRACK_NEGATIVE_Z"
tr.up_axis = "UP_Y"

# ---------------------------------------------------------------- animation (12 fps, 120 frames = 10 s)
sc.render.fps = FPS
sc.frame_start, sc.frame_end = 1, FRAMES


def ease(t):
    return t * t * (3 - 2 * t)


for f in range(1, FRAMES + 1):
    t = (f - 1) / (FRAMES - 1)
    s = (f - 1) / FPS
    e = ease(t)
    cam.location = (-0.55 + 0.95 * e, -3.75 + 0.55 * e, 1.02 + 0.10 * e)
    cam.keyframe_insert("location", frame=f)
    feather_root.rotation_euler = (feather_root.rotation_euler.x, feather_root.rotation_euler.y, feather_root.rotation_euler.z)
    head_root.rotation_euler = (math.radians(1.5 * math.sin(2 * math.pi * s / 5.0)), math.radians(2.5 * math.sin(2 * math.pi * s / 7.0 + 1)), math.radians(3 * math.sin(2 * math.pi * s / 6.0)))
    head_root.keyframe_insert("rotation_euler", frame=f)
    torso.scale = (0.25 * (1 + 0.012 * math.sin(2 * math.pi * s / 3.2)), 0.18 * (1 + 0.02 * math.sin(2 * math.pi * s / 3.2)), 0.28)
    torso.keyframe_insert("scale", frame=f)
    blink = 1.0
    for bt in (2.9, 7.1):
        d = abs(s - bt)
        if d < 0.13:
            blink = 0.08
    for er in eye_roots:
        er.scale = (1, 1, blink)
        er.keyframe_insert("scale", frame=f)
    for c, g in enumerate(CLOUDS):
        g.location = (g.location.x if f > 1 else g.location.x, 16, g.location.z)
        g.delta_location = (0.025 * f * (1 + 0.3 * c), 0, 0)
        g.keyframe_insert("delta_location", frame=f)
    for i, p in enumerate(PETALS):
        ph = (s / 10 + i / len(PETALS)) % 1.0
        x = -1.6 + 3.4 * ph + 0.25 * math.sin(2 * math.pi * (ph * 2 + i * 0.3))
        z = 2.3 - 2.4 * ph
        y = -0.9 + 0.5 * ((i * 37) % 7) / 7
        p.location = (x, y, z)
        p.rotation_euler = (ph * 9 + i, ph * 6, ph * 4 + i)
        p.keyframe_insert("location", frame=f)
        p.keyframe_insert("rotation_euler", frame=f)
# the feather sways on its own empty (layered on the head motion)
feather_base_rot = feather_root.rotation_euler.copy()
for f in range(1, FRAMES + 1):
    s = (f - 1) / FPS
    feather_root.rotation_euler = (feather_base_rot.x + math.radians(4 * math.sin(2 * math.pi * s / 2.6)),
                                   feather_base_rot.y + math.radians(5 * math.sin(2 * math.pi * s / 3.4 + 0.7)), feather_base_rot.z)
    feather_root.keyframe_insert("rotation_euler", frame=f)

# ---------------------------------------------------------------- render settings: CPU Cycles, toon, outlines on the child only
r = sc.render
r.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = int(os.environ.get("KR_SAMPLES", 12))
sc.cycles.use_denoising = True
sc.cycles.max_bounces = 3
r.resolution_x, r.resolution_y, r.resolution_percentage = W, H, 100
sc.view_settings.view_transform = "Standard"
sc.view_settings.look = "None"
LINES = os.environ.get("KR_LINES", "hull")   # hull (fast, geometry), freestyle (slow, single-threaded), 0 (none)
r.use_freestyle = LINES == "freestyle"
if LINES == "hull":
    # inverted-hull outlines: a slightly larger copy of each part with flipped normals, black where it faces the camera
    # from behind (the rim around the silhouette), transparent elsewhere. Cycles ignores backface culling, so the
    # Backfacing output does the culling in the shader.
    om = bpy.data.materials.new("outline")
    om.use_nodes = True
    ont = om.node_tree
    ont.nodes.clear()
    o_out = ont.nodes.new("ShaderNodeOutputMaterial")
    o_geo = ont.nodes.new("ShaderNodeNewGeometry")
    o_ink = ont.nodes.new("ShaderNodeEmission")
    o_ink.inputs[0].default_value = (0.012, 0.006, 0.012, 1)
    o_tr = ont.nodes.new("ShaderNodeBsdfTransparent")
    o_mix = ont.nodes.new("ShaderNodeMixShader")
    ont.links.new(o_geo.outputs["Backfacing"], o_mix.inputs[0])
    ont.links.new(o_ink.outputs[0], o_mix.inputs[1])
    ont.links.new(o_tr.outputs[0], o_mix.inputs[2])
    o_lp = ont.nodes.new("ShaderNodeLightPath")   # only the camera sees the outline; light and shadow rays pass through
    o_mix2 = ont.nodes.new("ShaderNodeMixShader")
    ont.links.new(o_lp.outputs["Is Camera Ray"], o_mix2.inputs[0])
    ont.links.new(o_tr.outputs[0], o_mix2.inputs[1])
    ont.links.new(o_mix.outputs[0], o_mix2.inputs[2])
    ont.links.new(o_mix2.outputs[0], o_out.inputs[0])
    skip = ("iris", "pupil", "shine", "mouth", "nose", "tilak", "brow", "lash", "bead", "barb", "stem", "fold", "pleat")
    for ob in CHAR.all_objects:
        if ob.type != "MESH" or ob.name.startswith(skip):
            continue
        if len(ob.material_slots) < 2:
            ob.data.materials.append(None) if len(ob.data.materials) < 2 else None
        ob.material_slots[1].link = "OBJECT"
        ob.material_slots[1].material = om
        sc_ = sum(ob.matrix_world.to_scale()) / 3
        mod = ob.modifiers.new("outline", "SOLIDIFY")
        mod.thickness = 0.0075 / max(sc_, 1e-3)
        mod.offset = 1.0
        mod.use_flip_normals = True
        mod.use_rim = False
        mod.material_offset = 1
r.line_thickness_mode = "ABSOLUTE"
r.line_thickness = 1.6 * W / 720
ls = bpy.context.view_layer.freestyle_settings.linesets[0]
ls.select_by_collection = True
ls.collection = CHAR
ls.select_silhouette, ls.select_border, ls.select_crease = True, True, False
ls.linestyle.color = (0.10, 0.06, 0.10)
r.image_settings.file_format = "PNG"

if MODE == "still":
    f = int(argv[2]) if len(argv) > 2 else 60
    sc.frame_set(f)
    r.filepath = os.path.join(OUT, f"still_{f:03d}.png")
    bpy.ops.render.render(write_still=True)
else:
    a, b = (int(argv[2]), int(argv[3])) if len(argv) > 3 else (1, FRAMES)
    sc.frame_start, sc.frame_end = a, b
    r.filepath = os.path.join(OUT, "f_")
    bpy.ops.render.render(animation=True)
