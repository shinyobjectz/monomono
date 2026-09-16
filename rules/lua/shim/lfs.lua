-- A pure-Lua stand-in for luafilesystem, enough for luacheck: attributes, currentdir, dir, mkdir.
-- Shells out; only ever on the path of the hermetic luacheck toolchain.
local lfs = { _VERSION = "LuaFileSystem 1.8.0" }
local function sh(cmd)
  local p = io.popen(cmd .. " 2>/dev/null")
  local out = p:read("a") or ""
  p:close()
  return out
end
local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
function lfs.attributes(path, attr)
  local mode = sh("if [ -d " .. q(path) .. " ]; then echo directory; elif [ -e " .. q(path) .. " ]; then echo file; fi"):gsub("%s+$", "")
  if mode == "" then return nil, path .. ": No such file or directory" end
  local t = { mode = mode, modification = tonumber(sh("stat -f %m " .. q(path) .. " 2>/dev/null || stat -c %Y " .. q(path))) or 0 }
  if attr then return t[attr] end
  return t
end
function lfs.currentdir() return (sh("pwd"):gsub("%s+$", "")) end
function lfs.dir(path)
  local names = { ".", ".." }
  for n in sh("ls -A " .. q(path)):gmatch("[^\n]+") do names[#names + 1] = n end
  local i = 0
  return function() i = i + 1; return names[i] end
end
function lfs.mkdir(path) return os.execute("mkdir -p " .. q(path)) end
function lfs.chdir() return nil, "chdir is not supported by the monomono lfs shim" end
return lfs
