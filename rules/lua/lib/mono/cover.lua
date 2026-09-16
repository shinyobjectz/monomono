-- Line coverage runner: lua cover.lua MAIN args...   (wrapper uses it when MONO_LUA_HOOK=cover)
-- Writes MONO_COVERAGE_OUT (default coverage.txt) as lcov-style records for every file under the project.
local main = table.remove(arg, 1)
arg[0] = main
local hits = {}
debug.sethook(function(_, line)
  local info = debug.getinfo(2, "S")
  local src = info and info.source
  if src and src:sub(1, 1) == "@" then
    local f = src:sub(2)
    hits[f] = hits[f] or {}
    hits[f][line] = (hits[f][line] or 0) + 1
  end
end, "l")
local okay, err = xpcall(function() dofile(main) end, debug.traceback)
debug.sethook()
local function realpath(p)
  local h = io.popen("realpath " .. string.format("%q", p) .. " 2>/dev/null || readlink -f " .. string.format("%q", p) .. " 2>/dev/null")
  local r = h and h:read("*l"); if h then h:close() end
  return (r and r ~= "") and r or p
end
local real = {}
for f, lines in pairs(hits) do
  if not f:find("/lib/mono/", 1, true) then
    local rp = realpath(f)
    real[rp] = real[rp] or {}
    for l, n in pairs(lines) do real[rp][l] = (real[rp][l] or 0) + n end
  end
end
hits = real
local out = assert(io.open(os.getenv("MONO_COVERAGE_OUT") or "coverage.txt", "w"))
local files, total_lines, hit_lines = {}, 0, 0
for f in pairs(hits) do files[#files + 1] = f end
table.sort(files)
for _, f in ipairs(files) do
  out:write("SF:", f, "\n")
  local lines = {}
  for l in pairs(hits[f]) do lines[#lines + 1] = l end
  table.sort(lines)
  for _, l in ipairs(lines) do out:write(("DA:%d,%d\n"):format(l, hits[f][l])) end
  -- count executable-looking lines that were never hit
  local fh = io.open(f, "r")
  local n, h = 0, #lines
  if fh then
    local ln = 0
    for text in fh:lines() do
      ln = ln + 1
      if text:match("%S") and not text:match("^%s*%-%-") and not text:match("^%s*end%s*$") and not text:match("^%s*else%s*$") then n = n + 1 end
    end
    fh:close()
  end
  out:write(("LH:%d\nLF:%d\nend_of_record\n"):format(h, math.max(n, h)))
  total_lines = total_lines + math.max(n, h)
  hit_lines = hit_lines + h
end
out:close()
io.stderr:write(("coverage: %d/%d lines (%.0f%%) -> %s\n"):format(hit_lines, total_lines, total_lines > 0 and 100 * hit_lines / total_lines or 0, os.getenv("MONO_COVERAGE_OUT") or "coverage.txt"))
if not okay then io.stderr:write(err, "\n") os.exit(1) end
