import { NodeIO } from '@gltf-transform/core';
import { resample } from '@gltf-transform/functions';
const [src, dst] = process.argv.slice(2);
const io = new NodeIO();
const doc = await io.read(src);
await doc.transform(resample({ tolerance: 0.0008 }));
await io.write(dst, doc);
