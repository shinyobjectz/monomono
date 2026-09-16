--- Resources: data files declared on a lua_library, found across every root on MONO_LUA_ROOTS.
local R = {}

local function roots()
  local out = {}
  for r in (os.getenv("MONO_LUA_ROOTS") or ""):gmatch("[^;]+") do out[#out + 1] = r end
  return out
end

--- Absolute path of a resource, or nil.
function R.path(rel)
  for _, root in ipairs(roots()) do
    local p = root .. "/" .. rel
    local f = io.open(p, "rb")
    if f then f:close() return p end
  end
  return nil
end

--- Contents of a resource, or error.
function R.read(rel)
  local p = R.path(rel)
  if not p then error("resource not found on any root: " .. rel, 2) end
  local f = assert(io.open(p, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

return R
