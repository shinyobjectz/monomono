-- Call profiler: lua profile.lua MAIN args...   (wrapper uses it when MONO_LUA_HOOK=profile)
-- Prints the top functions by inclusive time to stderr when the script ends.
local main = table.remove(arg, 1)
arg[0] = main
local clock = os.clock
local stack, totals, counts = {}, {}, {}
local function key(info)
  return ((info.short_src or "?") .. ":" .. tostring(info.linedefined) .. " " .. (info.name or "<anon>"))
end
debug.sethook(function(ev)
  if ev == "call" or ev == "tail call" then
    local info = debug.getinfo(2, "Sn")
    stack[#stack + 1] = { k = key(info), t = clock() }
  elseif ev == "return" then
    local top = table.remove(stack)
    if top then
      totals[top.k] = (totals[top.k] or 0) + (clock() - top.t)
      counts[top.k] = (counts[top.k] or 0) + 1
    end
  end
end, "cr")
local okay, err = xpcall(function() dofile(main) end, debug.traceback)
debug.sethook()
local rows = {}
for k, t in pairs(totals) do rows[#rows + 1] = { k = k, t = t, n = counts[k] } end
table.sort(rows, function(a, b) return a.t > b.t end)
io.stderr:write("profile: inclusive seconds, calls, function\n")
for i = 1, math.min(#rows, tonumber(os.getenv("MONO_PROFILE_TOP") or 20)) do
  io.stderr:write(("%9.6f %6d  %s\n"):format(rows[i].t, rows[i].n, rows[i].k))
end
if not okay then io.stderr:write(err, "\n") os.exit(1) end
