# Agent development notes

- Target the TI-Nspire CX II CAS built-in Lua script runtime. Keep the source in Lua and the deliverable in `.tns`; do not assume Ndless or desktop Lua libraries are present on the calculator.
- `app.lua` is the rpnspire entry point. Shared code lives in `rpn/`, `ui/`, `views/`, `ti/`, `apps/`, `dialog/`, and `config/`. Add focused modules there rather than editing generated `bundle.lua` or `.tns` files.
- Use TI scripting callbacks and documented APIs. The calculator omits standard `io`, `os`, `package`, `dofile`, and `loadfile`. Keep `platform.apiLevel` aligned with the APIs actually used.
- Run `npm ci`, `npm test`, and `npm run build` after relevant changes. `npm run build` bundles `app.lua` and converts `bundle.lua` to `rpn.tns` with Luna v2.1. `npm run build:hello` exercises direct `.lua` to `.tns` conversion.
- The VCE Specialist toolkit lives in `apps/vce/` (solvers in `apps/vce/solvers/`), with `views/sheet.lua` and `ui/mathbox.lua` for the UI. `vce.lua` is its standalone entry point (`npm run build:vce` writes `vce.tns`); `apps/vce/launcher.lua` adds it to rpnspire's app list. See `doc/vce.md`.
- `npm test` also runs `test_vce.lua`, which tests solvers against the numeric CAS mock in `testcas.lua`; the mock is not the TI CAS. The calculator runs Lua 5.1, so also run `make test LUA=lua5.1` and `lua5.1 tools/bundle_smoke.lua vce_bundle.lua` after building. Modules are bundled with `-p "./?.lua"`, so do not rely on `init.lua` module resolution.
- A successful Lua test or Luna conversion does not prove the document opens or behaves correctly on a CX II CAS. Record desktop software or handheld validation separately.

TI scripting API: https://education.ti.com/download/en/ed-tech/A92DC9082F53421788AD2109B976C98C/CBFF18971B214F9798E148B15051EC7B/TI-NspireScriptingInterface.pdf
