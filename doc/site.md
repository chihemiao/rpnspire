# Website

`site/` is the download and help website for the VCE toolkit. It runs as a
Cloudflare Worker named `vce-maths-toolkit`, with static files and a D1
database.

The site has five parts:

- **Downloads:** `vce_zh.tns` (Chinese + English) and `vce.tns` (English
  only), with the version, the changelog and how to update. "Send to
  calculator" puts a file straight on a connected CX II (see below).
- **Highlights:** four worked examples (function graph, areas/volumes of
  revolution, kinematics, SUVAT). Each one shows two ways side by side:
  - the commands you would type into a TI-Nspire Calculator page;
  - the same question typed into the toolkit, running live.
- **All topics:** the home-screen list from `apps/vce/registry.lua`, with
  MM/SM badges, plus an online playground.
- **Feedback form:** a required email and message, an optional name and
  edition, and an "email me about updates" box.
- **FAQ.**

## How the live screen works

`site/public/emu/` runs the real toolkit in the browser:

- `host.lua` provides the TI-Nspire scripting API: `gc` drawing,
  `platform`, `on.*` events, `toolpalette`, `clipboard`. Drawing goes into a
  command buffer.
- `core.js` runs `host.lua` and the bundle in Lua 5.4 compiled to WebAssembly
  ([wasmoon](https://github.com/ceifa/wasmoon)).
- `emulator.js` replays the buffer on a 318×212 canvas under a document tab
  bar, keeping the CX II screen's proportions at any size. It also maps
  keys, clicks and the on-screen keypad to calculator events, and draws the
  menu key's toolpalette.

The bundle comes from `site/emu/web.lua`. That is the normal entry (with
`vce.lua` and `vce_zh.lua`) running on the numeric mock CAS
(`testcas.lua`). The mock cannot simplify, so `site/emu/recorded.lua` holds
the exact answers the TI CAS gives for the four website examples. Questions
that visitors type themselves show decimals or unsimplified forms, and the
page says so.

The worked examples live in `site/public/assets/tutorials.js`. Each step of
the toolkit side is a key script, e.g. `'50{enter}20{enter}0{enter}'`.
`site/test/emu.test.mjs` plays every script in English and bilingual mode
and checks the answers in `expect`.

If you change a solver, run that test. When a CAS string the solver sends
changes, update `recorded.lua`. `assets/timath.js` draws the
Calculator-page entries as 2D maths.

## Sending to the calculator

`site/public/assets/nspire-usb.js` sends a `.tns` to a TI-Nspire CX II over
WebUSB, so it needs Chrome or Edge on a computer. The first press shows the
browser's device picker; after that the browser remembers the calculator.
Other browsers just download the file, and the page tells them how to send it
in one click.

The CX II wraps NavNet packets in "NavNet SE" messages. The code follows
[libnspire](https://github.com/Vogtinator/libnspire) (GPLv3, the library
behind n-link). TILP's libticalcs uses the same NavNet layout and checksum.
The steps are:

1. Answer the calculator's address and time requests, acking every message
   that asks for an ack.
2. Assign the address.
3. Open the file service `0x4060`.
4. Send `03 01`, the path, and the size.
5. Send the data in 1439-byte chunks, each starting with `05`.
6. Read the `FF 00` status.
7. Close the service.

The file goes to My Documents as `/vce_zh.tns` or `/vce.tns`.

`site/test/usb.test.mjs` runs the sender against a simulated calculator that
checks every message: checksums, acks, addresses, the file bytes, split and
merged USB reads, damaged messages and the error paths. The simulation follows
the same descriptions, so only a real handheld proves it works. When a send
fails, the page shows the technical message and a link to TI's CX II Connect.

## Build and test locally

```sh
npm ci && npm ci --prefix site
LUA=lua5.4 npm run build:site   # vce.tns, vce_zh.tns, then site/dist
npm run test:site               # live-screen tutorials, Worker (in-memory SQLite), USB sender
cd site && npx wrangler dev     # http://localhost:8787 with a local D1
```

`site/build.mjs` does the following:

- copies `site/public` to `site/dist`;
- bundles the web entry and vendors wasmoon;
- copies the two `.tns` files to `/downloads/` under stable and versioned
  names;
- packs the source code (GPL-3.0) into a source archive;
- writes `version.json` and `features.json`;
- fills the version, sizes, topics and changelog into `index.html`.

## Deploy

`.github/workflows/site.yml` builds and tests the site on every push to
`main` and to `claude/ti-nspire-math-tool-l6e103`. It deploys with
`wrangler deploy` when these repository secrets are set
(Settings › Secrets and variables › Actions):

| Secret | |
| --- | --- |
| `CLOUDFLARE_API_TOKEN` | required. Cloudflare › My Profile › API Tokens › Create Token › "Edit Cloudflare Workers", plus **Account › D1 › Edit** |
| `CLOUDFLARE_ACCOUNT_ID` | only if the token can see more than one account |
| `ADMIN_TOKEN` | optional. A long random password for `/admin` (feedback viewer) |

Without the token, the workflow still builds and tests the site and only
skips the deploy. The site is served at
`https://vce-maths-toolkit.<your-subdomain>.workers.dev`; a custom domain can
be added in the Cloudflare dashboard (Workers › vce-maths-toolkit › Settings
› Domains & Routes).

`site/wrangler.jsonc` binds the D1 database `vce-maths-toolkit-feedback`.
The Worker creates the `feedback` table if it is missing.

## Release an update

1. Raise the version in `apps/vce/version.lua`. The calculator shows it in
   the Help title bar.
2. Add an entry at the top of `site/changelog.json` with the same version, in
   both `zh` and `en`. The build fails if the two disagree.
3. Push. The workflow builds the new `.tns` files and deploys the site. The
   download links stay the same, and versioned copies
   (`/downloads/vce-2.1.tns`) stay available.
4. To email people who asked for update news, export the list from `/admin`
   (tick "只看要通知更新的") or query D1:
   `SELECT email FROM feedback WHERE notify = 1`.

## Feedback

Messages are stored in D1. For each message the Worker keeps:

- the email, the optional name and the message;
- the edition, the app version and the "notify" choice;
- the page language;
- a salted hash of the sender's IP address. It is used for a limit of 5
  messages per 10 minutes, and the address itself is not stored.

A hidden field catches simple bots. To read the messages, open `/admin` and
enter `ADMIN_TOKEN`, or query the database in the Cloudflare dashboard (D1 ›
vce-maths-toolkit-feedback › Console).
