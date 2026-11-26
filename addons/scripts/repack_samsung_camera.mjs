#!/usr/bin/env node
//
// repack_samsung_camera.mjs - swap patched *.dex files into a *Samsung-signed* APK
// without touching its APK Signing Block or META-INF/CERT.* entries.
//
// Why: SamsungCamera holds signature-level Samsung permissions and takes a different
// (privileged) code path than a re-signed build. Re-signing the APK with a debug key
// makes it crash at startup with:
//   java.lang.NoSuchMethodError: No static method asInterface(Landroid/os/IBinder;)
//     Lcom/samsung/android/camera/ICameraServiceWorker;
//     at CameraServiceWorkerWrapperImpl_V2.<init>
// The ROM does not verify the v2/v3 digests, so keeping the original Samsung block and
// only replacing dex payloads (CRC/size/offset fields patched) is enough.
//
// Usage:
//   node addons/scripts/repack_samsung_camera.mjs \
//        --base   cam_fw/_chk/dev.apk \
//        --rebuild cam_fw/newapk/rebuild.apk \
//        --out    cam_fw/newapk/dev_samsung_signed.apk
//
//   --entries classes2.dex,classes5.dex   only these entries (default: every classes*.dex
//                                          whose payload differs between --base/--rebuild)
//
// The script re-parses the archive itself (EOCD -> central directory -> local headers),
// so it works for STORED and DEFLATED entries and keeps entry order untouched.

import fs from 'node:fs';
import zlib from 'node:zlib';
import crypto from 'node:crypto';

const EOCD_SIG = 0x06054b50;
const SIG_BLOCK_MAGIC = 'APK Sig Block 42';

const CRC_TABLE = new Uint32Array(256);
for (let n = 0; n < 256; n++) {
  let c = n;
  for (let k = 0; k < 8; k++) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
  CRC_TABLE[n] = c >>> 0;
}
const crc32 = (buf) => {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
};

function parse(buf) {
  let eocd = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 65558); i--) {
    if (buf.readUInt32LE(i) === EOCD_SIG) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error('EOCD not found');
  const total = buf.readUInt16LE(eocd + 10);
  const cdOff = buf.readUInt32LE(eocd + 16);
  const trailing = Number(buf.readBigUInt64LE(cdOff - 24));
  const magic = buf.subarray(cdOff - 16, cdOff).toString('latin1');
  const sbStart = magic === SIG_BLOCK_MAGIC ? cdOff - (trailing + 8) : cdOff;

  const entries = [];
  let p = cdOff;
  for (let i = 0; i < total; i++) {
    const nameLen = buf.readUInt16LE(p + 28);
    const extraLen = buf.readUInt16LE(p + 30);
    const commentLen = buf.readUInt16LE(p + 32);
    const lho = buf.readUInt32LE(p + 42);
    const localNameLen = buf.readUInt16LE(lho + 26);
    const localExtraLen = buf.readUInt16LE(lho + 28);
    const csize = buf.readUInt32LE(p + 20);
    entries.push({
      name: buf.subarray(p + 46, p + 46 + nameLen).toString('latin1'),
      cdPos: p,
      cdLen: 46 + nameLen + extraLen + commentLen,
      method: buf.readUInt16LE(p + 10),
      csize,
      lho,
      localNameLen,
      localExtraLen,
      end: lho + 30 + localNameLen + localExtraLen + csize,
    });
    p += 46 + nameLen + extraLen + commentLen;
  }
  const maxEnd = Math.max(...entries.map((e) => e.end));
  return { eocd, cdOff, sbStart, total, entries, maxEnd, magic };
}

function payload(apkBuf, entry) {
  const start = entry.lho + 30 + entry.localNameLen + entry.localExtraLen;
  return Buffer.from(apkBuf.subarray(start, start + entry.csize));
}

function rewrite(baseBuf, replacements) {
  const z = parse(baseBuf);
  if (z.magic !== SIG_BLOCK_MAGIC) throw new Error('base APK has no APK Signing Block - refusing to repack');

  const localParts = [];
  const newOffsets = [];
  const encoded = new Map();
  let pos = 0;
  z.entries.forEach((e, idx) => {
    const dataStart = e.lho + 30 + e.localNameLen + e.localExtraLen;
    const header = Buffer.from(baseBuf.subarray(e.lho, dataStart));
    let data = baseBuf.subarray(dataStart, dataStart + e.csize);
    if (replacements.has(e.name)) {
      const raw = replacements.get(e.name);
      const out = e.method === 8 ? zlib.deflateRawSync(raw, { level: 9 }) : raw;
      encoded.set(e.name, out);
      header.writeUInt32LE(crc32(raw), 14);
      header.writeUInt32LE(out.length, 18);
      header.writeUInt32LE(raw.length, 22);
      data = out;
    }
    newOffsets[idx] = pos;
    localParts.push(Buffer.from(header), Buffer.from(data));
    pos += header.length + data.length;
  });

  const gap = baseBuf.subarray(z.maxEnd, z.sbStart);
  const signBlock = baseBuf.subarray(z.sbStart, z.cdOff);
  const cdParts = [];
  z.entries.forEach((e, idx) => {
    const cd = Buffer.from(baseBuf.subarray(e.cdPos, e.cdPos + e.cdLen));
    if (replacements.has(e.name)) {
      const raw = replacements.get(e.name);
      const out = encoded.get(e.name);
      cd.writeUInt32LE(crc32(raw), 16);
      cd.writeUInt32LE(out.length, 20);
      cd.writeUInt32LE(raw.length, 24);
    }
    cd.writeUInt32LE(newOffsets[idx], 42);
    cdParts.push(cd);
  });

  const cdBuf = Buffer.concat(cdParts);
  const body = Buffer.concat([...localParts, gap, signBlock, cdBuf]);
  const eocd = Buffer.from(baseBuf.subarray(z.eocd, baseBuf.length));
  eocd.writeUInt32LE(cdBuf.length, 12);
  eocd.writeUInt32LE(pos + gap.length + signBlock.length, 16);
  return Buffer.concat([body, eocd]);
}

function arg(name, dflt = undefined) {
  const i = process.argv.indexOf(`--${name}`);
  if (i < 0) return dflt;
  return process.argv[i + 1];
}

const basePath = arg('base');
const rebuildPath = arg('rebuild');
const outPath = arg('out');
const only = arg('entries');
if (!basePath || !rebuildPath || !outPath) {
  console.error('usage: node repack_samsung_camera.mjs --base stock.apk --rebuild rebuilt.apk --out out.apk [--entries classes2.dex,classes5.dex]');
  process.exit(2);
}

const base = fs.readFileSync(basePath);
const rebuild = fs.readFileSync(rebuildPath);
const baseParsed = parse(base);
const rebuildParsed = parse(rebuild);

const wanted = only ? new Set(only.split(',').map((s) => s.trim()).filter(Boolean))
  : new Set(baseParsed.entries.filter((e) => /^classes\d*\.dex$/.test(e.name)).map((e) => e.name));

const replacements = new Map();
for (const name of wanted) {
  const b = baseParsed.entries.find((e) => e.name === name);
  const r = rebuildParsed.entries.find((e) => e.name === name);
  if (!b) { console.warn(`skip ${name}: not present in base`); continue; }
  if (!r) { console.warn(`skip ${name}: not present in rebuild`); continue; }
  const rawBase = payload(base, b);
  const rawNew = payload(rebuild, r);
  if (rawBase.equals(rawNew)) { console.log(`${name}: unchanged`); continue; }
  replacements.set(name, rawNew);
  console.log(`${name}: ${rawBase.length} -> ${rawNew.length} bytes (sha256 ${crypto.createHash('sha256').update(rawNew).digest('hex').slice(0, 12)})`);
}

if (replacements.size === 0) {
  console.log('nothing to do');
  process.exit(0);
}

const outBuf = rewrite(base, replacements);
fs.writeFileSync(outPath, outBuf);
console.log(`wrote ${outPath} (${outBuf.length} bytes)`);

const check = parse(outBuf);
if (check.magic !== SIG_BLOCK_MAGIC) throw new Error('output lost its APK Signing Block');
for (const [name, raw] of replacements) {
  const e = check.entries.find((x) => x.name === name);
  const round = payload(outBuf, e);
  const actual = e.method === 8 ? zlib.inflateRawSync(round) : round;
  if (!actual.equals(raw)) throw new Error(`verification failed for ${name}`);
}
console.log('verified: signer block intact and every replaced entry round-trips');
