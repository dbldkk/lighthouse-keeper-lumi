#!/usr/bin/env python3
"""v1.3.2 patch for the user's v1.3.1 keeper model (Meshy-based, retopologized in Blender 5.x).

The Blender 5.x .blend cannot be opened in the Blender 4.2 we have on the build box, and an
import/export round trip through 4.2 would re-encode the mesh, skin and animations. So this
script edits the GLB data *in place* and keeps everything else bit-identical:

  1. Arm skinning: sleeve vertices (found by geodesic distance over the welded surface)
     get weights only from Chest / UpperArm / Forearm / Hand of their side, blended by geodesic
     distance (smooth elbow/wrist, shoulder mostly upper arm + some chest, no Pelvis/Spine).
  2. Lantern grip: in the "lantern" clip the Lantern bone rotated around its own origin (the
     lantern body, 22 cm under the grip) and the handle swung out of the hand. Translation keys
     are recomputed so the handle top stays in the palm for every rotation key.
  3. Colours (vertex colours, linear): coat lifted to the concept-B grey-green, the knit
     sweater in the coat opening warmed to brown, scarf to slate blue-grey.
  4. Face: a small skinned decal (eyes, brows, tired shadow under the eyes) bound to the Head
     bone, projected onto the face surface 1.4 mm out; texture drawn procedurally (tools/model/keeper_face_decal.png).

Input:  tools/model/keeper_v01_v131_source.glb  (pristine v1.3.1 export)
Output: assets/models/characters/keeper_v01.glb
Needs:  python3 with numpy + scipy + pillow.   Run:  python3 tools/model/patch_keeper_glb.py
"""
import json, struct, sys, os
import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import dijkstra

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "tools/model/keeper_v01_v131_source.glb")
DST = os.path.join(ROOT, "assets/models/characters/keeper_v01.glb")
FLAGS = set(sys.argv[1:])   # e.g. --no-weights --no-colors for before/after comparisons

raw = open(SRC, "rb").read()
jlen = struct.unpack("<I", raw[12:16])[0]
J = json.loads(raw[20:20 + jlen])
blen = struct.unpack("<I", raw[20 + jlen:24 + jlen])[0]
BIN = bytearray(raw[28 + jlen:28 + jlen + blen])

CT = {5126: np.float32, 5123: np.uint16, 5121: np.uint8, 5125: np.uint32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}

def view(i):
    """numpy view (copy) + writer for accessor i."""
    a = J["accessors"][i]; bv = J["bufferViews"][a["bufferView"]]
    dt = np.dtype(CT[a["componentType"]]).newbyteorder("<"); n = NC[a["type"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    st = bv.get("byteStride", dt.itemsize * n)
    out = np.empty((a["count"], n), dt)
    for k in range(a["count"]):
        out[k] = np.frombuffer(BIN, dt, n, off + k * st)
    def write(arr):
        arr = np.asarray(arr, dt).reshape(a["count"], n)
        if st == dt.itemsize * n:
            BIN[off:off + arr.nbytes] = arr.tobytes()
        else:
            for k in range(a["count"]):
                BIN[off + k * st:off + k * st + dt.itemsize * n] = arr[k].tobytes()
    return out, write

def fast(i):
    a = J["accessors"][i]; bv = J["bufferViews"][a["bufferView"]]
    dt = np.dtype(CT[a["componentType"]]).newbyteorder("<"); n = NC[a["type"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    assert bv.get("byteStride", dt.itemsize * n) == dt.itemsize * n
    arr = np.frombuffer(bytes(BIN[off:off + a["count"] * n * dt.itemsize]), dt).reshape(a["count"], n).copy()
    def write(new):
        new = np.ascontiguousarray(np.asarray(new, dt).reshape(a["count"], n))
        BIN[off:off + new.nbytes] = new.tobytes()
    return arr, write

nodes = J["nodes"]; skin = J["skins"][0]
joint_names = [nodes[k]["name"] for k in skin["joints"]]
JI = {n: i for i, n in enumerate(joint_names)}
ibm, _ = fast(skin["inverseBindMatrices"])
bind_world = [np.linalg.inv(m.reshape(4, 4).T) for m in ibm]      # joint rest matrices (world)
head = {n: bind_world[i][:3, 3] for n, i in JI.items()}

body_mesh = next(m for m in J["meshes"] if m["name"] == "Keeper game topology")
prim = body_mesh["primitives"][0]; at = prim["attributes"]
P, _ = fast(at["POSITION"]); P = P.astype(np.float64)
NRM, _ = fast(at["NORMAL"])
JOINTS, write_joints = fast(at["JOINTS_0"])
W, write_weights = fast(at["WEIGHTS_0"])
COL, write_col = fast(at["COLOR_0"])
IDX, _ = fast(prim["indices"]); TRI = IDX.reshape(-1, 3).astype(np.int64)
nv = len(P)
report = {}

def seg_dist(p, a, b):
    ab = b - a; t = np.clip(((p - a) @ ab) / (ab @ ab), 0, 1)
    return np.linalg.norm(p - (a + t[:, None] * ab), axis=1)

# ------------------------------------------------------------------ 1. arm weights
if "--no-weights" not in FLAGS:
    key = np.round(P * 1e5).astype(np.int64)
    _, weld = np.unique(key, axis=0, return_inverse=True); weld = weld.ravel()
    nw = weld.max() + 1
    WP = np.zeros((nw, 3)); WP[weld] = P
    e = np.vstack([TRI[:, [0, 1]], TRI[:, [1, 2]], TRI[:, [2, 0]]])
    e = weld[e]; e = e[e[:, 0] != e[:, 1]]
    ln = np.linalg.norm(WP[e[:, 0]] - WP[e[:, 1]], axis=1) + 1e-6
    G = coo_matrix((np.r_[ln, ln], (np.r_[e[:, 0], e[:, 1]], np.r_[e[:, 1], e[:, 0]])), shape=(nw, nw)).tocsr()

    def geo(mask_w):
        src = np.nonzero(mask_w)[0]
        if len(src) == 0:
            return np.full(nw, np.inf)
        return dijkstra(G, indices=src, min_only=True)

    torso_core = (np.abs(WP[:, 0]) < .13) & (WP[:, 1] > .78) & (WP[:, 1] < 1.5)
    g_torso = geo(torso_core)
    chest_seed = (np.abs(WP[:, 0]) < .16) & (WP[:, 1] > 1.22) & (WP[:, 1] < 1.50)
    g_chest = geo(chest_seed)
    changed = 0
    for side, sx in (("L", -1), ("R", 1)):
        ua, fa, ha = head["UpperArm." + side], head["Forearm." + side], head["Hand." + side]
        hand_end = ha + (ha - fa) / np.linalg.norm(ha - fa) * .13
        segs = {"UpperArm." + side: (ua, fa, .075), "Forearm." + side: (fa, ha, .065), "Hand." + side: (ha, hand_end, .06)}
        g = {}
        for bone, (a, b, r) in segs.items():
            d = seg_dist(WP, a, b)
            seed = (d < r) & (WP[:, 0] * sx > .2)
            g[bone] = geo(seed)
        g_arm = np.minimum.reduce(list(g.values()))
        # sleeve: closer (over the surface) to the arm than to the torso core, on this side
        sleeve_w = (g_arm < g_torso * .85) & (WP[:, 0] * sx > .14) & (WP[:, 1] > .74) & (WP[:, 1] < 1.56)
        bones = ["Chest", "UpperArm." + side, "Forearm." + side, "Hand." + side]
        gm = np.vstack([g_chest, g[bones[1]], g[bones[2]], g[bones[3]]]).T[sleeve_w]
        gmin = gm.min(1, keepdims=True)
        tau = np.array([.030, .040, .032, .022])     # blend widths: soft shoulder/elbow, tighter wrist
        w = np.exp(-(gm - gmin) / tau)
        w[w < .03] = 0
        w /= w.sum(1, keepdims=True)
        idx_w = np.nonzero(sleeve_w)[0]
        lut = {wv: k for k, wv in enumerate(idx_w)}
        for vi in np.nonzero(np.isin(weld, idx_w))[0]:
            row = w[lut[weld[vi]]]
            JOINTS[vi] = [JI[bones[0]], JI[bones[1]], JI[bones[2]], JI[bones[3]]]
            W[vi] = row
            changed += 1
        report["sleeve_verts_" + side] = int(np.isin(weld, idx_w).sum())
    # sort influences by weight (cosmetic) and renormalise
    order = np.argsort(-W, axis=1)
    W = np.take_along_axis(W, order, 1); JOINTS = np.take_along_axis(JOINTS, order, 1)
    W = W / W.sum(1, keepdims=True)
    JOINTS[W == 0] = 0
    write_joints(JOINTS); write_weights(W.astype(np.float32))
    report["reweighted_verts"] = changed

# ------------------------------------------------------------------ 3/4. colours
if "--no-colors" not in FLAGS:
    C = COL.astype(np.float64) / 65535.0
    rgb = C[:, :3]
    lum = rgb @ np.array([.2126, .7152, .0722])
    sat = rgb.max(1) - rgb.min(1)
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    skinlike = (rgb[:, 0] > rgb[:, 2] * 1.45) & (lum > .12)
    sat = rgb.max(1) - rgb.min(1)
    hair = (y > 1.60) & (lum < .06)
    scarf = (y > 1.42) & (y < 1.62) & (np.abs(x) < .17) & ~skinlike & ~hair
    sweater = (np.abs(x) < .07) & (z > .07) & (y > 1.12) & (y < 1.42) & ~skinlike & (sat < .05)
    leather = (rgb[:, 0] - rgb[:, 2] > .025) & (lum < .2)            # satchel, strap, belt: keep
    coat = (y > .60) & (y < 1.47) & ~skinlike & ~scarf & ~sweater & ~leather & (sat < .04) & (lum > .03) & (lum < .22)
    def recolor(mask, target):
        if not mask.any():
            return
        rel = lum[mask] / max(np.median(lum[mask]), 1e-4)
        rel = np.clip(rel, .5, 1.7) ** .85
        rgb[mask] = np.clip(np.asarray(target)[None, :] * rel[:, None], 0, 1)
    recolor(coat, [.118, .138, .106])      # weathered grey-green wool (sRGB ~ 0.38/0.41/0.36)
    recolor(sweater, [.130, .080, .044])   # warm brown knit
    recolor(scarf, [.078, .092, .108])     # slate blue-grey
    report["coat_verts"] = int(coat.sum()); report["sweater_verts"] = int(sweater.sum()); report["scarf_verts"] = int(scarf.sum())
    C[:, :3] = rgb
    write_col(np.round(np.clip(C, 0, 1) * 65535).astype(np.uint16))

# ------------------------------------------------------------------ 2. lantern grip
new_blobs = []
if "--no-lantern" not in FLAGS:
    lantern_mesh = next(m for m in J["meshes"] if m["name"] == "keeper Body")   # the oil lantern
    LP, _ = fast(lantern_mesh["primitives"][0]["attributes"]["POSITION"])
    top = LP[LP[:, 1] > LP[:, 1].max() - .025].mean(0)          # handle top (rest, world)
    hand_w = bind_world[JI["Hand.R"]]
    grip_hand = (np.linalg.inv(hand_w) @ np.r_[top, 1])[:3]    # grip point in Hand.R space
    ln_node = nodes[skin["joints"][JI["Lantern"]]]
    t_rest = np.array(ln_node.get("translation", [0, 0, 0])); q_rest = np.array(ln_node.get("rotation", [0, 0, 0, 1]))
    def qrot(q, v):
        x_, y_, z_, w_ = q; u = np.array([x_, y_, z_])
        return 2 * (u @ v) * u + (w_ * w_ - u @ u) * v + 2 * w_ * np.cross(u, v)
    def qinv(q):
        return np.array([-q[0], -q[1], -q[2], q[3]]) / (q @ q)
    grip_lantern = qrot(qinv(q_rest), grip_hand - t_rest)
    lantern_joint = skin["joints"][JI["Lantern"]]
    for anim in J["animations"]:
        if anim["name"] != "lantern":
            continue
        rot_ch = next(c for c in anim["channels"] if c["target"]["node"] == lantern_joint and c["target"]["path"] == "rotation")
        tr_ch = next(c for c in anim["channels"] if c["target"]["node"] == lantern_joint and c["target"]["path"] == "translation")
        rs = anim["samplers"][rot_ch["sampler"]]
        Q, _ = fast(rs["output"])
        T = np.array([grip_hand - qrot(q / np.linalg.norm(q), grip_lantern) for q in Q.astype(np.float64)], np.float32)
        report["lantern_max_shift_m"] = float(np.linalg.norm(T - t_rest, axis=1).max())
        # new output accessor with one translation per rotation key, sharing the rotation key times
        new_blobs.append(T.tobytes())
        J["bufferViews"].append({"buffer": 0, "byteOffset": None, "byteLength": T.nbytes})
        J["accessors"].append({"bufferView": len(J["bufferViews"]) - 1, "componentType": 5126, "count": len(T), "type": "VEC3",
                               "min": T.min(0).tolist(), "max": T.max(0).tolist()})
        anim["samplers"].append({"input": rs["input"], "output": len(J["accessors"]) - 1, "interpolation": rs.get("interpolation", "LINEAR")})
        tr_ch["sampler"] = len(anim["samplers"]) - 1

# ------------------------------------------------------------------ 4. face decal (eyes, brows)
if "--no-face" not in FLAGS:
    from scipy.interpolate import griddata
    from PIL import Image, ImageDraw, ImageFilter
    import io
    X0, X1, Y0, Y1 = -.056, .056, 1.711, 1.749        # eye band under the bangs (measured from the mesh)
    EYE_Y, EYE_X = 1.7275, .030
    m = (P[:, 1] > 1.69) & (P[:, 1] < 1.77) & (np.abs(P[:, 0]) < .08) & (P[:, 2] > .05)
    cells = {}
    for i in np.nonzero(m)[0]:
        k = (round(P[i, 0] / .004), round(P[i, 1] / .004))
        if k not in cells or P[i, 2] > P[cells[k], 2]:
            cells[k] = i
    ci = np.array(list(cells.values()))
    nx, ny = 23, 9
    gx, gy = np.meshgrid(np.linspace(X0, X1, nx), np.linspace(Y1, Y0, ny))
    gz = griddata(P[ci, :2], P[ci, 2], (gx, gy), method="linear")
    gz = np.where(np.isnan(gz), griddata(P[ci, :2], P[ci, 2], (gx, gy), method="nearest"), gz)
    # normals from the grid, push 1.4 mm out
    dzdx = np.gradient(gz, axis=1) / ((X1 - X0) / (nx - 1)); dzdy = np.gradient(gz, axis=0) / (-(Y1 - Y0) / (ny - 1))
    nrm = np.dstack([-dzdx, -dzdy, np.ones_like(gz)]); nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    pos = np.dstack([gx, gy, gz]) + nrm * .0014
    uv = np.dstack([(gx - X0) / (X1 - X0), (Y1 - gy) / (Y1 - Y0)])
    V = pos.reshape(-1, 3).astype(np.float32); NN = nrm.reshape(-1, 3).astype(np.float32); UV = uv.reshape(-1, 2).astype(np.float32)
    tris = []
    for r in range(ny - 1):
        for c in range(nx - 1):
            a = r * nx + c; b = a + 1; d = a + nx; e2 = d + 1
            tris += [a, d, b, b, d, e2]
    IDXD = np.array(tris, np.uint16)
    JD = np.tile(np.array([JI["Head"], 0, 0, 0], np.uint8), (len(V), 1))
    WD = np.tile(np.array([1, 0, 0, 0], np.float32), (len(V), 1))
    # texture (4x supersampled), u across the face, v down
    TW, TH, SS = 512, 176, 4
    img = Image.new("RGBA", (TW * SS, TH * SS), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    def px(xm, ym):
        return ((xm - X0) / (X1 - X0) * TW * SS, (Y1 - ym) / (Y1 - Y0) * TH * SS)
    for sgn in (-1, 1):
        cx, cy = px(sgn * EYE_X, EYE_Y)
        ew, eh = .0118 / (X1 - X0) * TW * SS, .0043 / (Y1 - Y0) * TH * SS
        # soft shadow under the eye (tired)
        sh = Image.new("RGBA", img.size, (0, 0, 0, 0)); sd = ImageDraw.Draw(sh)
        sd.ellipse([cx - ew * 1.15, cy + eh * .2, cx + ew * 1.1, cy + eh * 2.6], fill=(60, 34, 30, 95))
        sh = sh.filter(ImageFilter.GaussianBlur(SS * 9)); img.alpha_composite(sh)
        # sclera (muted), iris, pupil, upper lid line, lower lid
        almond = [(cx - ew, cy + eh * .1), (cx - ew * .5, cy - eh * .85), (cx + ew * .25, cy - eh * .95), (cx + ew, cy - eh * .05),
                  (cx + ew * .45, cy + eh * .75), (cx - ew * .4, cy + eh * .8)]
        if sgn < 0:
            almond = [(2 * cx - ax, ay) for ax, ay in almond]
        dr.polygon(almond, fill=(168, 152, 136, 230))
        ir = eh * 1.0
        dr.ellipse([cx - ir, cy - ir * .95, cx + ir, cy + ir * 1.05], fill=(58, 46, 38, 255))
        dr.ellipse([cx - ir * .45, cy - ir * .4, cx + ir * .45, cy + ir * .5], fill=(14, 11, 10, 255))
        dr.ellipse([cx + sgn * ir * .25 - ir * .18, cy - ir * .55, cx + sgn * ir * .25 + ir * .18, cy - ir * .2], fill=(230, 220, 205, 220))
        dr.line(almond[:4] + [almond[3]], fill=(26, 17, 13, 255), width=int(SS * 5.5), joint="curve")
        lid = [(ax, ay - eh * .55) for ax, ay in almond[:4]]
        dr.line(lid, fill=(96, 58, 44, 120), width=int(SS * 4), joint="curve")
        dr.line(almond[3:] + [almond[0]], fill=(70, 44, 36, 170), width=int(SS * 1.6), joint="curve")
        # brow: hair strokes, inner end lower (worried, tired)
        bx0, by0 = px(sgn * .011, EYE_Y + .0122)
        bx1, by1 = px(sgn * .048, EYE_Y + .0150)
        base = Image.new("RGBA", img.size, (0, 0, 0, 0)); bd = ImageDraw.Draw(base)
        pts_top, pts_bot = [], []
        for k in range(21):
            t = k / 20.0
            bx = bx0 + (bx1 - bx0) * t; by = by0 + (by1 - by0) * t - np.sin(t * np.pi) * SS * 8
            half = (1.15 - abs(t - .3) * 1.2) * SS * 9
            pts_top.append((bx, by - half)); pts_bot.append((bx, by + half))
        bd.polygon(pts_top + pts_bot[::-1], fill=(34, 24, 18, 200))
        base = base.filter(ImageFilter.GaussianBlur(SS * 2.2)); img.alpha_composite(base)
        for k in range(34):
            t = k / 33.0
            bx = bx0 + (bx1 - bx0) * t; by = by0 + (by1 - by0) * t - np.sin(t * np.pi) * SS * 8
            half = (1.15 - abs(t - .3) * 1.2) * SS * 8
            dr.line([(bx - sgn * SS * 4, by + half), (bx + sgn * SS * 7, by - half)], fill=(24, 17, 13, 210), width=int(SS * 2.6))
    img = img.resize((TW, TH), Image.LANCZOS)
    buf = io.BytesIO(); img.save(buf, "PNG"); png = buf.getvalue()
    pass
    def add_blob(data, target=None):
        new_blobs.append(data)
        bv = {"buffer": 0, "byteOffset": None, "byteLength": len(data)}
        if target:
            bv["target"] = target
        J["bufferViews"].append(bv)
        return len(J["bufferViews"]) - 1
    def add_acc(arr, ctype, typ, target=34962, minmax=False):
        bvi = add_blob(np.ascontiguousarray(arr).tobytes(), target)
        acc = {"bufferView": bvi, "componentType": ctype, "count": len(arr), "type": typ}
        if minmax:
            acc["min"] = arr.min(0).tolist(); acc["max"] = arr.max(0).tolist()
        J["accessors"].append(acc)
        return len(J["accessors"]) - 1
    a_pos = add_acc(V, 5126, "VEC3", minmax=True)
    a_nrm = add_acc(NN, 5126, "VEC3")
    a_uv = add_acc(UV, 5126, "VEC2")
    a_j = add_acc(JD, 5121, "VEC4")
    a_w = add_acc(WD, 5126, "VEC4")
    a_i = add_acc(IDXD, 5123, "SCALAR", target=34963)
    J.setdefault("images", []).append({"name": "keeper_face_decal", "mimeType": "image/png", "bufferView": add_blob(png)})
    J.setdefault("samplers", []).append({"magFilter": 9729, "minFilter": 9987, "wrapS": 33071, "wrapT": 33071})
    J.setdefault("textures", []).append({"sampler": len(J["samplers"]) - 1, "source": len(J["images"]) - 1})
    J["materials"].append({"name": "keeper face decal", "alphaMode": "BLEND", "doubleSided": False,
        "pbrMetallicRoughness": {"baseColorTexture": {"index": len(J["textures"]) - 1}, "metallicFactor": 0, "roughnessFactor": .75}})
    J["meshes"].append({"name": "keeper FaceDecal", "primitives": [{"attributes": {"POSITION": a_pos, "NORMAL": a_nrm, "TEXCOORD_0": a_uv,
        "JOINTS_0": a_j, "WEIGHTS_0": a_w}, "indices": a_i, "material": len(J["materials"]) - 1}]})
    J["nodes"].append({"name": "FaceDecal", "mesh": len(J["meshes"]) - 1, "skin": 0})
    rig = next(n for n in J["nodes"] if n["name"] == "Rig")
    rig["children"].append(len(J["nodes"]) - 1)
    open(os.path.join(ROOT, "tools/model/keeper_face_decal.png"), "wb").write(png)
    report["face_decal"] = {"verts": len(V), "tris": len(IDXD) // 3, "png_bytes": len(png)}

# ------------------------------------------------------------------ write
pending = [b for b in J["bufferViews"] if "byteOffset" in b and b["byteOffset"] is None]
assert len(pending) == len(new_blobs)
for bv, blob in zip(pending, new_blobs):
    while len(BIN) % 4:
        BIN.append(0)
    bv["byteOffset"] = len(BIN)
    BIN += blob
while len(BIN) % 4:
    BIN.append(0)
J["buffers"][0]["byteLength"] = len(BIN)
J.setdefault("asset", {})["extras"] = {"lumi_patch": "v1.3.2 tools/model/patch_keeper_glb.py"}
js = json.dumps(J, separators=(",", ":")).encode()
js += b" " * ((4 - len(js) % 4) % 4)
out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(BIN)) + struct.pack("<I4s", len(js), b"JSON") + js + struct.pack("<I4s", len(BIN), b"BIN\x00") + bytes(BIN)
open(sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else DST, "wb").write(out)
print(json.dumps(report, ensure_ascii=False))
