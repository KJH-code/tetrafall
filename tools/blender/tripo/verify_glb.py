# 만든 tank.glb 를 다시 읽어 자세별로 그림 (판 LOD 갈라짐 확인): blender -b --factory-startup -P verify_glb.py -- <tank.glb> <폴더> <lod 이름들 쉼표>
import bpy
import sys
import os
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import rig_tank as R  # noqa: E402


def main():
    glb, outdir, lods = sys.argv[sys.argv.index("--") + 1:][:3]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    arm = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"][0]
    print("TF 뼈", len(arm.data.bones), sorted(b.name for b in arm.data.bones))
    os.makedirs(outdir, exist_ok=True)
    for ln in lods.split(","):
        ob = [o for o in bpy.context.scene.objects if o.type == "MESH" and ln in o.name][0]
        print("TF", ob.name, R.tri_count(ob))
        R.render_poses(arm, ob, outdir, ln)


main()
