.PHONY: check syntax manifest test

LUA_FILES := $(shell find events outfits scripts tests -type f -name '*.lua' -print)

check: syntax manifest test

syntax:
	@for file in $(LUA_FILES); do luac -p "$$file" || exit 1; done

manifest:
	@python3 -c 'import tomllib; tomllib.load(open("plugin.toml", "rb")); tomllib.load(open("start.toml", "rb"))'

test:
	@lua tests/policy.lua
	@lua tests/runtime.lua
	@lua tests/event.lua
	@lua tests/outfit.lua
	@lua tests/scenario.lua
	@if command -v luajit >/dev/null 2>&1; then luajit tests/policy.lua; fi
	@if command -v luajit >/dev/null 2>&1; then luajit tests/runtime.lua; fi
	@if command -v luajit >/dev/null 2>&1; then luajit tests/event.lua; fi
	@if command -v luajit >/dev/null 2>&1; then luajit tests/outfit.lua; fi
	@if command -v luajit >/dev/null 2>&1; then luajit tests/scenario.lua; fi
