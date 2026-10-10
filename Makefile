LUA=lua
LUACHECK=luacheck
LUABUNDLER=luabundler

all: test

test: *.lua
	$(LUA) test.lua
	$(LUA) test_vce.lua

bundle: *.lua
	$(LUABUNDLER) bundle app.lua -p "./?.lua" -o bundle.lua

check: bundle
	$(LUACHECK) bundle.lua

tns: bundle
	./build.sh

vce-bundle: *.lua
	$(LUABUNDLER) bundle vce.lua -p "./?.lua" -o vce_bundle.lua

vce: vce-bundle
	./build.sh vce_bundle.lua vce.tns

vce-zh-bundle: *.lua
	$(LUABUNDLER) bundle vce_zh.lua -p "./?.lua" -o vce_zh_bundle.lua

vce-zh: vce-zh-bundle
	./build.sh vce_zh_bundle.lua vce_zh.tns
