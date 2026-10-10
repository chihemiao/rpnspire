// Tests the WebUSB sender (public/assets/nspire-usb.js) against a simulated
// TI-Nspire CX II (fakecalc.mjs). Run: node site/test/usb.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';
import { FakeCalc, crcBits } from './fakecalc.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const sandbox = { TextEncoder, setTimeout, clearTimeout };
vm.runInNewContext(fs.readFileSync(path.join(ROOT, 'site/public/assets/nspire-usb.js'), 'utf8'), sandbox);
const { NspireUSB } = sandbox;

const random = (n) => Uint8Array.from({ length: n }, () => Math.floor(Math.random() * 256));
const NOW = 1760000000123;
const fast = { timeout: 300, now: () => Date.now() };

const tests = {
  async 'checksums match independent versions'() {
    const t = NspireUSB._test;
    for (let i = 0; i < 300; i++) {
      const d = random(Math.floor(Math.random() * 400));
      assert.equal(t.crc16(d), crcBits(d));
      assert.equal(t.sum16(t.message({ service: 4, data: d })), 0xffff);
    }
  },

  async 'sends a file: handshake, address, put, chunks, close'() {
    const calc = new FakeCalc();
    const file = random(3000);
    const seen = [];
    await NspireUSB.sendFile(calc, '/vce_zh.tns', file, { now: () => NOW, onProgress: (a, b) => seen.push([a, b]) });
    assert.deepEqual(calc.files['/vce_zh.tns'], file);
    assert.equal(calc.addrResp, 2, 'address answer sent twice, as libnspire does');
    assert.equal(calc.timeResp, Math.floor(NOW / 1000));
    assert.equal(calc.needAck.size, 0, 'every calculator message acked');
    assert.equal(calc.nack.dstSid, 0x4050, 'stray packet refused');
    assert.deepEqual([...calc.nack.data], [0x40, 0x50]);
    assert.ok(calc.disconnected && calc.released && !calc.opened, 'closed cleanly');
    assert.ok(calc.wasReset);
    assert.deepEqual(seen.at(-1), [3000, 3000]);
    assert.equal(seen.length, 4, '0, then 3 chunks of up to 1439 bytes');
  },

  async 'short name and small file'() {
    const calc = new FakeCalc();
    const file = random(200);
    await NspireUSB.sendFile(calc, '/a.tns', file, { now: () => NOW });
    assert.deepEqual(calc.files['/a.tns'], file);
  },

  async 'the real documents, read in pieces'() {
    for (const name of ['vce.tns', 'vce_zh.tns']) {
      const file = new Uint8Array(fs.readFileSync(path.join(ROOT, name)));
      const calc = new FakeCalc({ split: true });
      await NspireUSB.sendFile(calc, '/' + name, file, { now: () => NOW });
      assert.deepEqual(calc.files['/' + name], file, name);
    }
  },

  async 'drops a damaged message'() {
    const calc = new FakeCalc({ corrupt: true });
    const file = random(500);
    await NspireUSB.sendFile(calc, '/x.tns', file, { now: () => NOW });
    assert.deepEqual(calc.files['/x.tns'], file);
  },

  async 'goes on when the calculator skips the handshake'() {
    const calc = new FakeCalc({ noHandshake: true });
    const file = random(100);
    await NspireUSB.sendFile(calc, '/x.tns', file, fast);
    assert.deepEqual(calc.files['/x.tns'], file);
  },

  async 'errors say what went wrong'() {
    const code = async (opt, sendOpt = fast) => {
      const calc = new FakeCalc(opt);
      try {
        await NspireUSB.sendFile(calc, '/x.tns', random(3000), sendOpt);
      } catch (e) {
        assert.ok(!calc.claimed, 'interface released after ' + e.code);
        return e.code;
      }
      return 'ok';
    };
    assert.equal(await code({ busy: true }), 'busy');
    assert.equal(await code({ refuse: true }), 'refused');
    assert.equal(await code({ noAck: true }), 'timeout');
    assert.equal(await code({ unplugAfter: 6 }), 'lost');
    assert.equal(await code({ productId: 0xe012 }), 'model');
  },
};

let failed = 0;
for (const [name, fn] of Object.entries(tests)) {
  try {
    await fn();
    console.log('ok  ', name);
  } catch (e) {
    failed++;
    console.log('FAIL', name);
    console.log(e);
  }
}
if (failed) {
  console.log(`${failed} failed`);
  process.exit(1);
}
console.log('all passed');
