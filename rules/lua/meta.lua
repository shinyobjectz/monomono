-- meta.lua OUTDIR ROOTS_FILE [--provided=file]... name=path ...
-- LuaLS ---@meta stubs for every module, and a .luarc.json whose library paths come from the graph.
-- A stub keeps the module's own ---@ annotations and derives one from each `function M.x(a, b)` and `M.x = ...`.
local outdir, roots_file = arg[1], arg[2]
local luarc_out = outdir .. "/.luarc.json"
os.execute(("mkdir -p %q"):format(outdir))

local function read(p) local f = assert(io.open(p, "rb")); local s = f:read("*a"); f:close(); return s end

-- provided ---@meta files are copied in as they are; the modules they declare are not stubbed
local provided, skip = {}, {}
for i = #arg, 3, -1 do
  local p = arg[i]:match("^%-%-provided=(.*)$")
  if p then
    table.remove(arg, i)
    local src = read(p)
    for m in src:gmatch("%-%-%-@module%s+['\"]([^'\"]+)['\"]") do skip[m] = true end
    local f = assert(io.open(outdir .. "/" .. p:match("([^/]+)$"), "w")); f:write(src); f:close()
    provided[#provided + 1] = p
  end
end

local function stub(name, src)
  local lines = { "---@meta", ("---@module '%s'"):format(name), "" }
  -- `return function(...)` modules: the stub is the annotated function itself, not a table
  local nsrc = "\n" .. src
  local fparams = nsrc:match("\nreturn%s+function%s*%(([^)]*)%)%s*$") or nsrc:match("\nreturn%s+function%s*%(([^)]*)%)")
  if fparams and not nsrc:match("\nreturn%s+[%a_][%w_]*%s*$") then
    local before = nsrc:match("^(.-)\nreturn%s+function") or ""
    local anns = {}
    for line in (before .. "\n"):gmatch("(.-)\n") do
      local ann = line:match("^%s*(%-%-%-.*)$")
      if ann then anns[#anns + 1] = ann elseif line:match("%S") then anns = {} end
    end
    for _, a in ipairs(anns) do lines[#lines + 1] = a end
    lines[#lines + 1] = ("return function(%s) end"):format(fparams)
    return table.concat(lines, "\n") .. "\n"
  end
  -- the local table the module returns, if it is the usual shape
  local var = src:match("local%s+([%a_][%w_]*)%s*=%s*{}") or src:match("return%s+([%a_][%w_]*)%s*$") or "M"
  lines[#lines + 1] = ("local %s = {}"):format(var)
  local pending = {}
  for line in (src .. "\n"):gmatch("(.-)\n") do
    local ann = line:match("^%s*(%-%-%-.*)$")
    if ann then
      pending[#pending + 1] = ann
    else
      local fname, params = line:match("^%s*function%s+([%a_][%w_%.:]*)%s*%(([^)]*)%)")
      if fname and (fname:match("^" .. var .. "[%.:]") or fname:match("^[%a_][%w_]*%.")) then
        for _, a in ipairs(pending) do lines[#lines + 1] = a end
        local has_param = {}
        for _, a in ipairs(pending) do local p = a:match("@param%s+([%a_][%w_]*)"); if p then has_param[p] = true end end
        for p in params:gmatch("[%a_][%w_%.]*") do
          if p ~= "..." and not has_param[p] then lines[#lines + 1] = ("---@param %s any"):format(p) end
        end
        lines[#lines + 1] = ("function %s(%s) end"):format(fname, params)
        lines[#lines + 1] = ""
        pending = {}
      else
        local field = line:match("^%s*" .. var .. "%.([%a_][%w_]*)%s*=")
        if field and not line:match("=%s*function") then
          for _, a in ipairs(pending) do lines[#lines + 1] = a end
          lines[#lines + 1] = ("%s.%s = nil"):format(var, field)
          pending = {}
        elseif field then
          local params = line:match("=%s*function%s*%(([^)]*)%)") or ""
          for _, a in ipairs(pending) do lines[#lines + 1] = a end
          lines[#lines + 1] = ("function %s.%s(%s) end"):format(var, field, params)
          lines[#lines + 1] = ""
          pending = {}
        elseif line:match("%S") then
          pending = {}
        end
      end
    end
  end
  lines[#lines + 1] = ("return %s"):format(var)
  return table.concat(lines, "\n") .. "\n"
end

local written = {}
for i = 3, #arg do
  local name, path = arg[i]:match("^([^=]*)=(.*)$")
  if name and name ~= "" and not skip[name] then
    local rel = name:gsub("%.", "/") .. ".lua"
    local dir = rel:match("^(.*)/[^/]*$")
    if dir then os.execute(("mkdir -p %q"):format(outdir .. "/" .. dir)) end
    local f = assert(io.open(outdir .. "/" .. rel, "w"))
    f:write(stub(name, read(path)))
    f:close()
    written[#written + 1] = rel
  end
end

local roots = {}
for line in read(roots_file):gmatch("[^\n]+") do roots[#roots + 1] = line end
local libs = {}
for _, r in ipairs(roots) do libs[#libs + 1] = ('    "%s"'):format(r) end
libs[#libs + 1] = '    "."'   -- the stubs beside this file
local f = assert(io.open(luarc_out, "w"))
f:write(([[{
  "$schema": "https://raw.githubusercontent.com/LuaLS/vscode-lua/master/setting/schema.json",
  "runtime.version": "%s",
  "runtime.path": ["?.lua", "?/init.lua"],
  "workspace.library": [
%s
  ],
  "workspace.checkThirdParty": false,
  "diagnostics.globals": ["arg"]
}
]]):format(os.getenv("MONO_LUA_RUNTIME") or "Lua 5.4", table.concat(libs, ",\n")))
f:close()
io.stderr:write(("meta: %d stub(s), %d provided, %d root(s)\n"):format(#written, #provided, #roots))
