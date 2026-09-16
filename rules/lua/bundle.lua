-- bundle.lua OUT MAIN DIALECT name=path ...
-- One file. Each module is loaded at runtime from its own source string under its module name as chunk name,
-- so a stack trace inside a bundle says greet.util:3 (deterministic: no paths, modules in sorted order). DIALECT gates syntax the
-- target interpreter lacks (5.1 | 5.3 | 5.4 | jit | portable = 5.1 ∩ 5.4); a rejected file names the construct.
local out, main, dialect = arg[1], arg[2], arg[3]

local function read(p)
  local f = assert(io.open(p, "rb"))
  local s = f:read("*a")
  f:close()
  return (s:gsub("^#![^\n]*\n", ""))
end

-- strip comments and strings so the gate only sees code
local function code_only(src)
  src = src:gsub("%-%-%[(=*)%[.-%]%1%]", " ")
  src = src:gsub("%[(=*)%[.-%]%1%]", '""')
  src = src:gsub("%-%-[^\n]*", "")
  src = src:gsub('"[^"\n]*"', '""'):gsub("'[^'\n]*'", "''")
  return src
end

local GATES = {
  ["5.1"] = { { "<const>", "<const> (5.4)" }, { "<close>", "<close> (5.4)" }, { "//", "integer division (5.3)" },
              { "goto%s", "goto (5.2)" }, { "::%a", "label (5.2)" }, { "[^~=<>]~[^=]", "bitwise xor/not (5.3)" },
              { "%s&%s", "bitwise and (5.3)" }, { "%s|%s", "bitwise or (5.3)" }, { "<<", "shift (5.3)" }, { ">>", "shift (5.3)" } },
  ["jit"] = { { "<const>", "<const> (5.4)" }, { "<close>", "<close> (5.4)" }, { "//", "integer division (5.3)" },
              { "[^~=<>]~[^=]", "bitwise xor/not (5.3)" }, { "%s&%s", "bitwise and (5.3)" }, { "%s|%s", "bitwise or (5.3)" }, { "<<", "shift (5.3)" }, { ">>", "shift (5.3)" } },
  ["5.3"] = { { "<const>", "<const> (5.4)" }, { "<close>", "<close> (5.4)" } },
  ["5.4"] = {},
}
-- portable = the 5.1 ∩ 5.4 subset: everything 5.1 lacks, plus the library calls 5.1 lacks
GATES.portable = {}
for _, r in ipairs(GATES["5.1"]) do GATES.portable[#GATES.portable + 1] = r end
for _, r in ipairs({ { "utf8%%.", "utf8 library (5.3)" }, { "math%%.tointeger", "math.tointeger (5.3)" }, { "math%%.ult", "math.ult (5.3)" },
                     { "table%%.move", "table.move (5.3)" }, { "string%%.pack", "string.pack (5.3)" }, { "string%%.unpack", "string.unpack (5.3)" },
                     { "coroutine%%.close", "coroutine.close (5.4)" }, { "warn%%(", "warn (5.4)" } }) do
  GATES.portable[#GATES.portable + 1] = r
end

local function gate(path, src)
  local rules = GATES[dialect]
  if not rules then error("unknown dialect: " .. tostring(dialect)) end
  local code = code_only(src)
  for _, r in ipairs(rules) do
    if code:find(r[1]) then
      io.stderr:write(("%s: uses %s, which dialect %s does not have\n"):format(path, r[2], dialect))
      os.exit(1)
    end
  end
end

local function level_for(s)
  local n = 0
  while s:find("]" .. string.rep("=", n) .. "]", 1, true) do n = n + 1 end
  return string.rep("=", n)
end

local o = assert(io.open(out, "wb"))
o:write("-- bundled by monomono lua_bundle; do not edit\n")
for i = 4, #arg do
  local name, path = arg[i]:match("^([^=]*)=(.*)$")
  if name and name ~= "" then
    local src = read(path)
    gate(path, src)
    local eq = level_for(src)
    o:write(("package.preload[%q] = assert((loadstring or load)([%s[\n%s]%s], %q, \"t\"))\n"):format(name, eq, src, eq, "=" .. name))
  end
end
local msrc = read(main)
gate(main, msrc)
o:write("-- main\n", msrc, "\n")
o:close()
