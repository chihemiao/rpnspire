// A simulated TI-Nspire CX II for the USB sender tests (usb.test.mjs) and for
// trying the page in a browser. It follows the protocol as libnspire and TILP
// describe it and checks every message it gets; it is not the real calculator.
import assert from 'node:assert/strict';

// Written separately from the module so a shared mistake cannot hide
export function sum16(b) {
  let acc = 0;
  for (let i = 0; i < b.length; i += 2) acc += (b[i] << 8) | (i + 1 < b.length ? b[i + 1] : 0);
  return acc % 0xffff || (acc ? 0xffff : 0);
}
export function crcBits(d) {
  let r = 0;
  for (const b of d) {
    for (let i = 0; i < 8; i++) {
      const out = r & 1;
      r = (r >>> 1) | (((b >> i) & 1) << 15);
      if (out) r ^= 0x8408;
    }
  }
  return r;
}
const u16 = (b, i) => (b[i] << 8) | b[i + 1];
const be16 = (v) => [(v >> 8) & 0xff, v & 0xff];

function nnse(f) {
  const data = f.data || [];
  const m = new Uint8Array(12 + data.length);
  m.set([f.misc || 0, f.service, f.src ?? 0x01, f.dest ?? 0xfe, f.unknown || 0, f.reqAck || 0, ...be16(m.length), ...be16(f.seqno)]);
  m.set(data, 12);
  m.set(be16(sum16(m) ^ 0xffff), 10);
  return m;
}
function navnet(f) {
  const big = f.data.length >= 0xff;
  const body = big ? [...[24, 16, 8, 0].map((s) => (f.data.length >>> s) & 0xff), ...f.data] : [...f.data];
  const p = [0x54, 0xfd, ...be16(f.srcAddr), ...be16(f.srcSid), ...be16(f.dstAddr), ...be16(f.dstSid),
    ...be16(crcBits(body)), big ? 0xff : f.data.length, f.ack || 0, f.seq || 0];
  p.push(p.reduce((a, b) => a + b, 0) & 0xff);
  return Uint8Array.from([...p, ...body]);
}
function readNavnet(p) {
  assert.ok(p.length >= 16, 'NavNet header');
  assert.equal(u16(p, 0), 0x54fd, 'NavNet magic');
  assert.equal(p.subarray(0, 15).reduce((a, b) => a + b, 0) & 0xff, p[15], 'NavNet header checksum');
  const big = p[12] === 0xff;
  const n = big ? ((p[16] << 24) | (p[17] << 16) | (p[18] << 8) | p[19]) >>> 0 : p[12];
  const body = p.subarray(16, 16 + (big ? 4 : 0) + n);
  assert.equal(16 + body.length, p.length, 'NavNet length');
  assert.equal(crcBits(body), u16(p, 10), 'NavNet data checksum');
  if (big) assert.ok(n >= 0xff && n <= 1440, 'big packets hold 255..1440 bytes');
  return {
    srcAddr: u16(p, 2), srcSid: u16(p, 4), dstAddr: u16(p, 6), dstSid: u16(p, 8), ack: p[13], seq: p[14],
    data: big ? body.subarray(4) : body,
  };
}

// A CX II as far as sending one file goes
export class FakeCalc {
  constructor(opt = {}) {
    this.opt = opt;
    this.vendorId = 0x0451;
    this.productId = opt.productId ?? 0xe022;
    this.productName = 'TI-Nspire CX II CAS';
    // opt.heldOpen: this page left it open and claimed; opt.unconfigured: no
    // active configuration yet; opt.iface1: a decoy interface 0 before the
    // NavNet one; opt.busy / opt.busyTimes: the claim fails always / n times
    this.opened = !!opt.heldOpen;
    this.claimed = !!opt.heldOpen;
    this.configuration = opt.unconfigured ? null : FakeCalc.config(opt);
    this.claims = 0;
    this.halts = [];
    this.queue = [];      // bytes the calculator will send
    this.pending = null;  // a transferIn waiting for bytes
    this.seq = 0x1000;
    this.needAck = new Map(); // seqno -> where the message went
    this.log = [];
    this.files = {};
    this.addrResp = 0;
    this.timeResp = null;
    this.handshaken = false;
    this.addressed = false;
  }

  static config(opt) {
    const navnet = { interfaceClass: 0xff, endpoints: [
      { endpointNumber: 1, direction: 'in', type: 'bulk', packetSize: 512 },
      { endpointNumber: 1, direction: 'out', type: 'bulk', packetSize: 512 },
      { endpointNumber: 2, direction: 'out', type: 'bulk', packetSize: 512 },
    ] };
    const decoy = { interfaceClass: 0x03, endpoints: [{ endpointNumber: 3, direction: 'in', type: 'interrupt', packetSize: 8 }] };
    const interfaces = opt.iface1
      ? [{ interfaceNumber: 0, alternate: decoy }, { interfaceNumber: 1, alternate: navnet }]
      : [{ interfaceNumber: 0, alternate: navnet }];
    return { configurationValue: 1, interfaces };
  }

  async open() {
    assert.ok(!this.opened, 'opened twice without closing');
    this.opened = true;
  }
  async close() {
    this.opened = false;
    this.claimed = false;
    if (this.pending) { this.pending.reject(new Error('device closed')); this.pending = null; }
  }
  async selectConfiguration(v) {
    assert.ok(this.opened);
    assert.equal(v, 1);
    this.configuration = FakeCalc.config(this.opt);
  }
  // a reset re-enumerates on macOS and the browser loses the device
  async reset() { this.wasReset = true; }
  async claimInterface(n) {
    assert.ok(this.opened, 'open before claiming');
    assert.equal(n, this.opt.iface1 ? 1 : 0, 'the NavNet interface');
    this.claims++;
    if (this.opt.busy || this.claims <= (this.opt.busyTimes || 0)) {
      throw Object.assign(new Error('Unable to claim interface.'), { name: 'NetworkError' });
    }
    assert.ok(!this.claimed, 'claimed twice');
    this.claimed = true;
    if (this.opt.noHandshake) { this.handshaken = true; return; }
    const id = new TextEncoder().encode('            TI-Nspire CX II CAS'.padEnd(64, '\0'));
    this.say({ service: 0x01, dest: 0xff, reqAck: 1, data: [0x00, ...id] });
    this.say({ service: 0x08, reqAck: 1, data: [0x01] });
    if (this.opt.corrupt) {
      const bad = nnse({ service: 0x02, reqAck: 1, data: [0x00], seqno: 0x0fff });
      bad[12] ^= 0x40;
      this.push(bad);
    }
    this.say({ service: 0x02, reqAck: 1, data: [0x00] });
  }
  async releaseInterface(n) {
    assert.equal(n, this.opt.iface1 ? 1 : 0);
    this.claimed = false;
    this.released = true;
  }
  async clearHalt(dir, ep) {
    assert.ok(this.claimed);
    this.halts.push(dir + ep);
  }

  say(f) {
    const m = nnse({ ...f, seqno: this.seq++ });
    if (f.reqAck & 1) this.needAck.set(u16(m, 8), m[3]);
    this.push(m);
  }
  push(bytes) {
    this.queue.push(bytes);
    this.feed();
  }
  reply(to, data, extra = {}) {
    this.say({ service: 0x04, reqAck: 1, data: navnet({
      srcAddr: 0x6401, srcSid: 0x4060, dstAddr: 0x6400, dstSid: to.srcSid, data, ...extra,
    }) });
  }

  // Bytes go out whole, or cut in pieces and run together when opt.split is set
  feed() {
    if (!this.pending || !this.queue.length) return;
    let out;
    if (this.opt.split) {
      const all = Uint8Array.from(this.queue.flatMap((b) => [...b]));
      const n = Math.min(all.length, 1 + Math.floor(Math.random() * 40));
      out = all.slice(0, n);
      this.queue = n < all.length ? [all.slice(n)] : [];
    } else {
      out = this.queue.shift();
    }
    const { resolve } = this.pending;
    this.pending = null;
    resolve({ status: 'ok', data: new DataView(out.buffer, out.byteOffset, out.byteLength) });
  }

  transferIn(ep, len) {
    assert.equal(ep, 1);
    assert.ok(len >= 1484, 'reads room for a whole message');
    if (this.opt.unplugAfter !== undefined && this.log.length >= this.opt.unplugAfter) {
      return Promise.reject(new Error('The device was disconnected.'));
    }
    assert.equal(this.pending, null, 'one transferIn at a time');
    return new Promise((resolve, reject) => {
      this.pending = { resolve, reject };
      setTimeout(() => this.feed(), 0);
    });
  }

  async transferOut(ep, data) {
    assert.equal(ep, 1);
    assert.ok(this.claimed, 'interface claimed before writing');
    const m = Uint8Array.from(data);
    assert.equal(sum16(m), 0xffff, 'NNSE checksum');
    assert.equal(u16(m, 6), m.length, 'NNSE length');
    assert.equal(m[3], 0x01, 'to the calculator');
    const service = m[1];
    const body = m.subarray(12);
    this.log.push(service);
    if (service & 0x80) {
      // an ack swaps the addresses, so a broadcast is acked from 0xFF
      assert.ok(this.needAck.has(u16(m, 8)), 'ack for a message that wanted one');
      assert.equal(m[2], this.needAck.get(u16(m, 8)), 'ack comes from where the message went');
      this.needAck.delete(u16(m, 8));
      assert.equal(m[5] & 1, 0, 'acks do not ask for acks');
      return { status: 'ok', bytesWritten: m.length };
    }
    assert.equal(m[2], 0xfe, 'from the computer');
    if (service === 0x01) {
      assert.deepEqual([...body], [0x80]);
      this.addrResp++;
    } else if (service === 0x02) {
      assert.equal(body.length, 17);
      assert.equal(body[0], 0x80);
      this.timeResp = ((body[1] << 24) | (body[2] << 16) | (body[3] << 8) | body[4]) >>> 0;
      this.handshaken = true;
    } else if (service === 0x08) {
      assert.deepEqual([...body], [0x81, 0x03]);
    } else if (service === 0x04) {
      assert.equal(m[5], 1, 'stream messages want an ack');
      assert.ok(this.handshaken, 'handshake before NavNet');
      if (!this.opt.noAck) this.push(nnse({ service: 0x84, reqAck: 0, seqno: u16(m, 8) }));
      this.navnet(readNavnet(body));
    } else {
      assert.fail('unexpected service ' + service);
    }
    return { status: 'ok', bytesWritten: m.length };
  }

  navnet(p) {
    assert.equal(p.srcAddr, 0x6400);
    assert.equal(p.dstAddr, 0x6401);
    if (p.srcSid === 0x4003) {
      assert.deepEqual([p.dstSid, ...p.data], [0x4003, 0x64, 0x01, 0xff, 0x00]);
      this.addressed = true;
      // something the page did not ask for, which it should refuse
      this.say({ service: 0x04, reqAck: 1, data: navnet({
        srcAddr: 0x6401, srcSid: 0x4050, dstAddr: 0x6400, dstSid: 0x4050, seq: 1, data: [0x01, 0x02],
      }) });
    } else if (p.srcSid === 0xd3) {
      this.nack = p;
    } else if (p.srcSid === 0x40de) {
      assert.equal(p.dstSid, 0x4060);
      assert.deepEqual([...p.data], [0x80, 0x00]);
      this.disconnected = true;
    } else if (p.dstSid === 0x4060 && p.data[0] === 0x03) {
      assert.ok(this.addressed, 'address before the file service');
      assert.equal(p.data[1], 0x01);
      const end = p.data.indexOf(0, 2);
      this.name = new TextDecoder().decode(p.data.subarray(2, end));
      const stored = Math.max(end - 2, 8) + 1;
      const at = 2 + stored;
      assert.equal(p.data.length, at + 4, 'name padded to 8, then the size');
      this.size = ((p.data[at] << 24) | (p.data[at + 1] << 16) | (p.data[at + 2] << 8) | p.data[at + 3]) >>> 0;
      this.got = [];
      this.reply(p, this.opt.refuse ? [0x0f] : [0x04]);
    } else if (p.dstSid === 0x4060 && p.data[0] === 0x05) {
      assert.ok(p.data.length <= 1440);
      this.got.push(...p.data.subarray(1));
      assert.ok(this.got.length <= this.size, 'no more than announced');
      if (this.got.length === this.size) {
        this.files[this.name] = Uint8Array.from(this.got);
        this.reply(p, [0xff, 0x00]);
      }
    } else {
      assert.fail('unexpected NavNet packet to ' + p.dstSid.toString(16));
    }
  }
}
