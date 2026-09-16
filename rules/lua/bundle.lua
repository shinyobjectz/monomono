-- bundle.lua OUT MAIN name=path ...
-- One file: every module registered in package.preload, then the main chunk.
local out, main = arg[1], arg[2]
local function read(p)
  local f = assert(io.open(p, "rb"))
  local s = f:read("a")
  f:close()
  return s:gsub("^#![^\n]*\n", "")
end
local o = assert(io.open(out, "wb"))
o:write("-- bundled by monomono lua_bundle; do not edit\n")
for i = 3, #arg do
  local name, path = arg[i]:match("^([^=]*)=(.*)$")
  if name and name ~= "" then
    o:write(("package.preload[%q] = function(...)\n%s\nend\n"):format(name, (read(path))))
  end
end
o:write("-- main\n", (read(main)), "\n")
o:close()
