--- monomono support library. Always on LUA_PATH for lua_binary, lua_test, lua_repl.
--- @module 'mono'
local mono = {}
mono.resource = require("mono.resource")
mono.spec = require("mono.spec")
mono.telemetry = require("mono.telemetry")
return mono
