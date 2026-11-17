# 자동 리깅 대포수 '두 손 묶음' 손질 (c9): <bpy 파이썬> tools/blender/tripo/rig_cannon_grip.py -- --out <폴더>   (blender -b --factory-startup -P … 도 같음)
# rig_cannon.py 와 같은 손질 (알베도 한 장·몸 색 칸 = 빨간 두건 + 다이너마이트 띠·1인칭 닫힌 팔 cannon_vm) 인데 **몸에서 손대포를 떼지 않음**:
#   판 몸 = 대포가 두 손에 붙은 채 cannon_lod0. 떼어 내면 주먹에 녹은 그루터기·뗀 자리 속 면이 남아 보라 조각·검은 삼각형이 됨 (README 13절 '한계').
#   대신 로더가 3인칭에서 팔·손가락 뼈를 쉬는 자세로 묶음 (cannon.json "grip": true, chars/ext_grip.gd) → 한 팔만 움직여 대포가 늘어나는 일이 없음.
#   1인칭 전용 소품 cannon_gun.glb 는 예전처럼 만듦 — 몸 복사본에서 떼어 내고 복사본은 버림 (cannon.json attach 의 "third": false).
# 그다음 LOD: node lods.mjs <out>/cannon_rigged.glb <out>/cannon.glb cannon 8000
import bpy
import sys
import os
import json
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import rigkit as K  # noqa: E402
import rig_cannon as C  # noqa: E402  (손질·대포 떼기·1인칭 팔 재사용)


def jpeg_drop_icc(d):
    """JPEG 바이트에서 ICC 구획 (APP2) 만 뺌 — 픽셀 자료는 그대로 (다시 압축 안 함)"""
    out = bytearray(d[:2])
    i = 2
    while i + 4 <= len(d) and d[i] == 0xFF:
        m = d[i + 1]
        n = int.from_bytes(d[i + 2:i + 4], "big")
        if m == 0xDA:  # 여기부터 픽셀 자료
            break
        if m != 0xE2:
            out += d[i:i + 2 + n]
        i += 2 + n
    return bytes(out + d[i:])


def strip_icc(path):
    """내보낸 glb 안 JPEG 의 ICC 프로필을 뗌: bpy 5.x 가 넣는 lcms ICC 구획을 고도 4.7 JPEG 읽기가 못 읽어 가져오기가 '이미지 못 읽음' → 텍스처 없는 몸이 됨.
    BIN 을 버퍼 뷰 순서대로 다시 쌓고 (4바이트 맞춤) 자리·길이를 고쳐 씀"""
    d = open(path, "rb").read()
    jl = struct.unpack("<I", d[12:16])[0]
    j = json.loads(d[20:20 + jl])
    b0 = 20 + jl + 8
    views = j.get("bufferViews", [])
    raw = [d[b0 + v.get("byteOffset", 0):b0 + v.get("byteOffset", 0) + v["byteLength"]] for v in views]
    cut = 0
    for im in j.get("images", []):
        if im.get("mimeType") == "image/jpeg" and "bufferView" in im:
            k = im["bufferView"]
            new = jpeg_drop_icc(raw[k])
            cut += len(raw[k]) - len(new)
            raw[k] = new
    out = bytearray()
    for k in sorted(range(len(views)), key=lambda k: views[k].get("byteOffset", 0)):
        out += b"\0" * (-len(out) % 4)
        views[k]["byteOffset"] = len(out)
        views[k]["byteLength"] = len(raw[k])
        out += raw[k]
    out += b"\0" * (-len(out) % 4)
    j["buffers"][0]["byteLength"] = len(out)
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(out)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(out), 0x004E4942) + bytes(out))
    print("TF ICC 구획 뗌 %s (%d 바이트)" % (os.path.basename(path), cut))


def main():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--out" not in a:
        raise SystemExit("--out <폴더> 가 필요함 (cannon_rigged.glb·cannon_gun.glb 를 거기에)")
    out = a[a.index("--out") + 1]
    ob, arm = C.build(a)
    # 손대포 소품: 몸 복사본에서 뗌 (split_gun 이 넘긴 메시에서 대포 삼각형을 지우므로) — 진짜 몸은 대포가 붙은 채
    tmp = ob.copy()
    tmp.data = ob.data.copy()
    bpy.context.scene.collection.objects.link(tmp)
    gun = C.split_gun(tmp, arm)
    bpy.data.objects.remove(tmp, do_unlink=True)
    print("TF 몸 삼각형 (대포 붙은 채) %d" % len(ob.data.polygons))
    C.export(os.path.join(out, "cannon_rigged.glb"), [ob, C.make_vm(ob, arm), arm])
    K.select([gun])
    bpy.ops.export_scene.gltf(filepath=os.path.join(out, "cannon_gun.glb"), export_format="GLB", use_selection=True, export_apply=False,
                              export_yup=True, export_texcoords=True, export_normals=True, export_materials="EXPORT", export_image_format="JPEG",
                              export_jpeg_quality=88, export_skins=False, export_animations=False, export_extras=False)
    for nm in ("cannon_rigged.glb", "cannon_gun.glb"):
        strip_icc(os.path.join(out, nm))
    print("TF 내보냄", out)


if __name__ == "__main__":
    main()
