import {NodeIO} from '@gltf-transform/core';
import {weld,simplify,textureCompress} from '@gltf-transform/functions';
import {MeshoptSimplifier} from 'meshoptimizer';
await MeshoptSimplifier.ready;
const io=new NodeIO();const d=await io.read(process.argv[2]);
await d.transform(weld(),simplify({simplifier:MeshoptSimplifier,ratio:+process.argv[4],error:0.02,lockBorder:false}));
await io.write(process.argv[3],d);
const p=d.getRoot().listMeshes()[0].listPrimitives()[0];console.log('tris',p.getIndices().getCount()/3);
