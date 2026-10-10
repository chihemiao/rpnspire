// Sends a .tns document to a TI-Nspire CX II over WebUSB (Chrome and Edge on
// a computer), so the website can put the toolkit on the calculator directly.
//
// The CX II speaks NavNet, TI's packet protocol of the earlier Nspires, wrapped
// in "NavNet SE" (NNSE) messages. This follows libnspire by Fabian Vogt and
// contributors (GPLv3, github.com/Vogtinator/libnspire: cx2.cpp, packet.c,
// data.c, services/file.c), which n-link uses with CX II calculators; TILP's
// libticalcs (nsp_rpkt.cc) has the same NavNet layout and checksum. Only the
// pieces needed to write one file are here. Not tested on a calculator by us.
(function (root) {
  'use strict';

  const VID = 0x0451;
  const PID_CX2 = 0xe022;

  // NNSE ---------------------------------------------------------------------
  // Header, big endian: misc, service, src, dest, unknown, reqAck (bit 0: ack
  // wanted), length (with header), seqno, checksum.
  const HDR = 12;
  const MAX = HDR + 1472;
  const ME = 0xfe;
  const ALL = 0xff;
  const CALC = 0x01;
  const ADDR = 0x01;
  const TIME = 0x02;
  const STREAM = 0x04;
  const UNKNOWN = 0x08;
  const ACKED = 0x80;

  // 16-bit one's complement sum of big-endian words; a whole message sums to 0xFFFF
  function sum16(b) {
    let acc = 0;
    for (let i = 0; i + 1 < b.length; i += 2) acc += (b[i] << 8) | b[i + 1];
    if (b.length & 1) acc += b[b.length - 1] << 8;
    while (acc > 0xffff) acc = (acc >>> 16) + (acc & 0xffff);
    return acc;
  }

  let seqno = 0; // one counter for every message we send, as in libnspire

  function message(f) {
    const data = f.data || [];
    const m = new Uint8Array(HDR + data.length);
    m[0] = f.misc || 0;
    m[1] = f.service;
    m[2] = f.src === undefined ? ME : f.src;
    m[3] = f.dest === undefined ? CALC : f.dest;
    m[4] = f.unknown || 0;
    m[5] = f.reqAck || 0;
    m[6] = m.length >> 8;
    m[7] = m.length & 0xff;
    const s = f.seqno === undefined ? (seqno++ & 0xffff) : f.seqno;
    m[8] = s >> 8;
    m[9] = s & 0xff;
    m.set(data, HDR);
    const c = sum16(m) ^ 0xffff;
    m[10] = c >> 8;
    m[11] = c & 0xff;
    return m;
  }

  function parse(m) {
    return {
      misc: m[0], service: m[1], src: m[2], dest: m[3], unknown: m[4], reqAck: m[5],
      seqno: (m[8] << 8) | m[9], data: m.subarray(HDR),
    };
  }

  // NavNet -------------------------------------------------------------------
  // Header, big endian: 0x54FD, src addr, src sid, dst addr, dst sid, data
  // checksum, size (0xFF: a 4-byte size follows), ack, seq, header checksum.
  const NAV = 16;
  const NAV_DATA = 1440;
  const HOST = 0x6400;
  const DEVICE = 0x6401;
  const FILES = 0x4060;

  // The data checksum as libnspire and TILP compute it: a CCITT CRC register
  // (reflected polynomial 0x8408) that the data bytes are shifted into
  function crc16(b) {
    let acc = 0;
    for (let i = 0; i < b.length; i++) {
      const first = ((b[i] << 8) | (acc >> 8)) & 0xffff;
      acc &= 0xff;
      const second = ((((acc & 0x0f) << 4) ^ acc) << 8) & 0xffff;
      const third = second >> 5;
      acc = (third >> 7) ^ first ^ second ^ third;
    }
    return acc & 0xffff;
  }

  function packet(f) {
    const data = f.data;
    const big = data.length >= 0xff;
    const body = new Uint8Array((big ? 4 : 0) + data.length);
    if (big) {
      body[0] = data.length >>> 24;
      body[1] = (data.length >> 16) & 0xff;
      body[2] = (data.length >> 8) & 0xff;
      body[3] = data.length & 0xff;
    }
    body.set(data, big ? 4 : 0);
    const p = new Uint8Array(NAV + body.length);
    const put16 = (i, v) => { p[i] = (v >> 8) & 0xff; p[i + 1] = v & 0xff; };
    put16(0, 0x54fd);
    put16(2, f.srcAddr === undefined ? HOST : f.srcAddr);
    put16(4, f.srcSid);
    put16(6, f.dstAddr === undefined ? DEVICE : f.dstAddr);
    put16(8, f.dstSid);
    put16(10, crc16(body));
    p[12] = big ? 0xff : data.length;
    p[13] = f.ack || 0;
    p[14] = f.seq || 0;
    let h = 0;
    for (let i = 0; i < NAV - 1; i++) h += p[i];
    p[15] = h & 0xff;
    p.set(body, NAV);
    return p;
  }

  function unpacket(p) {
    if (p.length < NAV) return null;
    const get16 = (i) => (p[i] << 8) | p[i + 1];
    let h = 0;
    for (let i = 0; i < NAV - 1; i++) h += p[i];
    if (get16(0) !== 0x54fd || (h & 0xff) !== p[15]) return null;
    let body;
    let data;
    if (p[12] === 0xff) {
      if (p.length < NAV + 4) return null;
      const n = ((p[16] << 24) | (p[17] << 16) | (p[18] << 8) | p[19]) >>> 0;
      if (p.length < NAV + 4 + n) return null;
      body = p.subarray(NAV, NAV + 4 + n);
      data = body.subarray(4);
    } else {
      if (p.length < NAV + p[12]) return null;
      body = p.subarray(NAV, NAV + p[12]);
      data = body;
    }
    if (crc16(body) !== get16(10)) return null;
    return {
      srcAddr: get16(2), srcSid: get16(4), dstAddr: get16(6), dstSid: get16(8),
      ack: p[13], seq: p[14], data,
    };
  }

  // A file name as NavNet sends it: zero padded to at least 8 bytes, then 0
  function padded(s) {
    const b = new TextEncoder().encode(s);
    const out = new Uint8Array(Math.max(b.length, 8) + 1);
    out.set(b);
    return out;
  }

  // Errors carry a code the page turns into advice
  function fail(code, detail) {
    const e = new Error(code + (detail ? ': ' + detail : ''));
    e.code = code;
    return e;
  }

  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  const why = (e) => (e && e.name && e.name !== 'Error' ? e.name + ': ' : '') + (e && e.message ? e.message : String(e));

  // The interface with a bulk IN and a bulk OUT endpoint, vendor class first;
  // endpoints 1 when there are several (libnspire uses 0x81 and 0x01)
  function findInterface(cfg) {
    let best = null;
    for (const itf of (cfg && cfg.interfaces) || []) {
      const alt = itf.alternate || (itf.alternates && itf.alternates[0]);
      if (!alt) continue;
      const bulk = (dir) => {
        const eps = alt.endpoints.filter((x) => x.direction === dir && x.type === 'bulk');
        return (eps.find((x) => x.endpointNumber === 1) || eps[0] || {}).endpointNumber;
      };
      const found = { number: itf.interfaceNumber, in: bulk('in'), out: bulk('out'), vendor: alt.interfaceClass === 0xff };
      if (found.in === undefined || found.out === undefined) continue;
      if (!best || (found.vendor && !best.vendor)) best = found;
    }
    return best;
  }

  // What the browser sees, for the error message
  function describe(d) {
    const cfg = d.configuration;
    if (!cfg) return 'no configuration';
    return 'config ' + cfg.configurationValue + '; ' + cfg.interfaces.map((itf) => {
      const alt = itf.alternate || {};
      const eps = (alt.endpoints || []).map((x) => x.direction + x.endpointNumber + (x.type === 'bulk' ? '' : x.type)).join(' ');
      return 'if' + itf.interfaceNumber + ' class ' + (alt.interfaceClass || 0).toString(16) + (itf.claimed ? ' claimed' : '') + ' ' + eps;
    }).join('; ');
  }

  // One connection to one calculator -----------------------------------------

  class Link {
    constructor(device, opts) {
      this.dev = device;
      this.timeout = opts.timeout || 10000;
      this.quiet = Math.min(opts.quiet || 3000, this.timeout);
      this.now = opts.now || (() => Date.now());
      this.buf = new Uint8Array(0);
      this.inbox = [];   // NNSE messages not yet looked at
      this.streams = []; // NavNet packets from the calculator
      this.waiter = null;
      this.error = null;
      this.closed = false;
      this.ready = false;
    }

    // No USB reset here: on macOS it re-enumerates the calculator and the
    // browser loses it. Another program may let go a moment later, so the
    // open and the claim are tried a few times.
    async open() {
      const d = this.dev;
      const step = async (name, fn) => {
        for (let i = 0; ; i++) {
          try {
            return await fn();
          } catch (e) {
            if (i >= 2) throw fail('busy', name + ': ' + why(e) + ' [' + describe(d) + ']');
            await wait(400);
          }
        }
      };
      // a connection this page left open would block the claim
      if (d.opened) { try { await d.close(); } catch (e) { /* start afresh */ } }
      await step('open', () => d.open());
      if (!d.configuration) await step('selectConfiguration(1)', () => d.selectConfiguration(1));
      const itf = findInterface(d.configuration);
      if (!itf) throw fail('device', 'no bulk interface [' + describe(d) + ']');
      await step('claimInterface(' + itf.number + ')', () => d.claimInterface(itf.number));
      this.iface = itf.number;
      this.epIn = itf.in;
      this.epOut = itf.out;
      // Clear both pipes so both ends start from DATA0 with nothing stalled
      try { await d.clearHalt('in', this.epIn); } catch (e) { /* not stalled */ }
      try { await d.clearHalt('out', this.epOut); } catch (e) { /* not stalled */ }
      this.read();
    }

    async close() {
      this.closed = true;
      if (this.iface !== undefined) {
        try { await this.dev.releaseInterface(this.iface); } catch (e) { /* already gone */ }
      }
      try { await this.dev.close(); } catch (e) { /* already gone */ }
    }

    // One transfer in flight at a time; messages may span or share transfers
    async read() {
      while (!this.closed) {
        let r;
        try {
          r = await this.dev.transferIn(this.epIn, MAX);
        } catch (e) {
          if (!this.closed) this.stop(fail('lost', 'transferIn: ' + why(e)));
          return;
        }
        if (r.status === 'stall') {
          try { await this.dev.clearHalt('in', this.epIn); } catch (e) { /* try reading anyway */ }
          continue;
        }
        if (!r.data || !r.data.byteLength) continue;
        const chunk = new Uint8Array(r.data.buffer, r.data.byteOffset, r.data.byteLength);
        const all = new Uint8Array(this.buf.length + chunk.length);
        all.set(this.buf);
        all.set(chunk, this.buf.length);
        this.buf = all;
        while (this.buf.length >= HDR) {
          const len = (this.buf[6] << 8) | this.buf[7];
          if (len < HDR || len > MAX) { this.buf = new Uint8Array(0); break; }
          if (this.buf.length < len) break;
          const m = this.buf.slice(0, len);
          this.buf = this.buf.slice(len);
          if (sum16(m) !== 0xffff) continue; // damaged: the calculator sends it again
          this.inbox.push(parse(m));
        }
        if (this.waiter && this.inbox.length) this.waiter();
      }
    }

    stop(err) {
      this.error = err;
      if (this.waiter) this.waiter();
    }

    // The next message from the calculator, or null after `ms`
    next(ms) {
      if (this.error) return Promise.reject(this.error);
      if (this.inbox.length) return Promise.resolve(this.inbox.shift());
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => { this.waiter = null; resolve(null); }, ms);
        this.waiter = () => {
          clearTimeout(timer);
          this.waiter = null;
          if (this.error) reject(this.error);
          else resolve(this.inbox.shift());
        };
      });
    }

    async write(m) {
      let r;
      try {
        r = await this.dev.transferOut(this.epOut, m);
      } catch (e) {
        throw fail('lost', 'transferOut: ' + why(e));
      }
      if (r.status !== 'ok' || r.bytesWritten !== m.length) throw fail('lost', 'short write');
    }

    // Answer what the calculator asks for (cx2.cpp handlePacket); keep its
    // NavNet packets for recv()
    async handle(m) {
      if (m.dest !== ME && m.dest !== ALL) return;
      if (m.service & ACKED) return;
      if (m.reqAck & 1) {
        await this.write(message({
          misc: m.misc, service: m.service | ACKED, src: m.dest, dest: m.src,
          unknown: m.unknown, reqAck: m.reqAck & ~1, seqno: m.seqno,
        }));
      }
      if (m.service === ADDR && m.data[0] === 0) {
        // Sent twice: after a reconnect the calculator may miss the first one
        await this.write(message({ service: ADDR, data: [0x80] }));
        await this.write(message({ service: ADDR, data: [0x80] }));
      } else if (m.service === TIME && m.data[0] === 0) {
        const sec = Math.floor(this.now() / 1000) >>> 0;
        const t = new Uint8Array(17);
        t[0] = 0x80;
        t[1] = sec >>> 24;
        t[2] = (sec >> 16) & 0xff;
        t[3] = (sec >> 8) & 0xff;
        t[4] = sec & 0xff;
        await this.write(message({ service: TIME, data: t }));
        this.ready = true;
      } else if (m.service === UNKNOWN && m.data.length === 1 && m.data[0] === 1) {
        await this.write(message({ service: UNKNOWN, data: [0x81, 0x03] }));
      } else if (m.service === STREAM) {
        this.streams.push(m.data.slice());
      }
    }

    // Wait for the calculator's address and time requests. One that has
    // said nothing for `quiet` ms may have done this already: go on.
    async handshake() {
      const end = this.now() + this.timeout;
      let heard = false;
      while (!this.ready) {
        const left = Math.min(end - this.now(), heard ? Infinity : this.quiet);
        if (left <= 0) break;
        const m = await this.next(left);
        if (!m) break;
        heard = true;
        await this.handle(m);
      }
      // A calculator that skipped the handshake may still listen: send() finds out
      this.ready = true;
    }

    // One NavNet packet in a stream message, then wait for its ack
    async send(fields) {
      const m = message({ service: STREAM, reqAck: 1, data: packet(fields) });
      const sent = (m[8] << 8) | m[9];
      await this.write(m);
      const end = this.now() + this.timeout;
      for (;;) {
        const left = end - this.now();
        const r = left > 0 ? await this.next(left) : null;
        if (!r) throw fail('timeout', 'no ack');
        if (r.dest === ME && r.service === (STREAM | ACKED) && r.seqno === sent) return;
        await this.handle(r);
      }
    }

    // The next NavNet packet for `sid`, answering others (data.c data_read)
    async recv(sid) {
      const end = this.now() + this.timeout;
      for (;;) {
        while (this.streams.length) {
          const p = unpacket(this.streams.shift());
          if (!p) throw fail('protocol', 'bad packet');
          if (p.dstSid === sid) return p.data;
          // Not ours: ack a disconnect, refuse anything else (data.c handle_unknown)
          await this.send({
            srcSid: p.dstSid === 0x40de ? (p.seq ? 0xff : 0xfe) : 0xd3,
            dstSid: p.srcSid, ack: 0x0a, seq: p.seq, data: [p.dstSid >> 8, p.dstSid & 0xff],
          });
        }
        const left = end - this.now();
        const r = left > 0 ? await this.next(left) : null;
        if (!r) throw fail('timeout', 'no reply');
        await this.handle(r);
      }
    }
  }

  // Put `bytes` at `path` ("/name.tns" is My Documents) -------------------------
  async function sendFile(device, path, bytes, opts) {
    opts = opts || {};
    const progress = opts.onProgress || (() => {});
    if (device.productId !== PID_CX2) throw fail('model', 'not a CX II');
    const link = new Link(device, opts);
    try {
      await link.open();
      await link.handshake();
      // Address assignment (init.c), then the file service (services/file.c)
      await link.send({ srcSid: 0x4003, dstSid: 0x4003, data: [0x64, 0x01, 0xff, 0x00] });
      const host = 0x8000;
      const name = padded(path);
      const head = new Uint8Array(2 + name.length + 4);
      head.set([0x03, 0x01]);
      head.set(name, 2);
      const n = bytes.length;
      head.set([n >>> 24, (n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff], 2 + name.length);
      await link.send({ srcSid: host, dstSid: FILES, data: head });
      const ok = await link.recv(host);
      if (ok[0] !== 0x04) throw fail('refused', 'reply ' + ok[0]);
      progress(0, n);
      for (let at = 0; at < n;) {
        const len = Math.min(NAV_DATA - 1, n - at);
        const chunk = new Uint8Array(len + 1);
        chunk[0] = 0x05;
        chunk.set(bytes.subarray(at, at + len), 1);
        await link.send({ srcSid: host, dstSid: FILES, data: chunk });
        at += len;
        progress(at, n);
      }
      const done = await link.recv(host);
      if (done[0] !== 0xff || done[1] !== 0x00) throw fail('refused', 'status ' + done[0] + ' ' + done[1]);
      // Close the file service (service.c service_disconnect)
      await link.send({ srcSid: 0x40de, dstSid: FILES, data: [host >> 8, host & 0xff] });
    } finally {
      await link.close();
    }
  }

  // A calculator this site may already use, else ask (needs a click)
  async function pickDevice() {
    const filters = [{ vendorId: VID, productId: PID_CX2 }];
    const known = (await navigator.usb.getDevices()).filter((d) => d.vendorId === VID && d.productId === PID_CX2);
    if (known.length) return known[0];
    try {
      return await navigator.usb.requestDevice({ filters });
    } catch (e) {
      if (e && e.name === 'NotFoundError') throw fail('cancelled');
      throw fail('busy', 'requestDevice: ' + why(e));
    }
  }

  root.NspireUSB = {
    supported: !!(root.navigator && root.navigator.usb),
    pickDevice,
    sendFile,
    _test: { sum16, crc16, message, parse, packet, unpacket, padded },
  };
})(typeof window !== 'undefined' ? window : globalThis);
