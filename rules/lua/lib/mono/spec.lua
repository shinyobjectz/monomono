--- A small test runner with named cases and TAP output.
---   local spec = require("mono.spec")
---   spec.test("adds", function() spec.eq(1 + 1, 2) end)
---   spec.run()   -- prints TAP, exits non-zero on failure
local S = { cases = {} }

function S.test(name, fn) S.cases[#S.cases + 1] = { name = name, fn = fn } end
S.it = S.test

local function fail(msg, level) error(setmetatable({ spec = true, msg = msg }, { __tostring = function(e) return e.msg end }), level or 3) end

function S.eq(got, want, label)
  if got ~= want then fail(("%sexpected %s, got %s"):format(label and (label .. ": ") or "", tostring(want), tostring(got))) end
end
function S.ok(v, label) if not v then fail((label or "assertion") .. " is falsy") end end
function S.err(fn, pattern)
  local okay, e = pcall(fn)
  if okay then fail("expected an error") end
  if pattern and not tostring(e):find(pattern) then fail(("error %q does not match %q"):format(tostring(e), pattern)) end
end
function S.same(a, b, path)
  path = path or "value"
  if type(a) ~= "table" or type(b) ~= "table" then return S.eq(a, b, path) end
  for k, v in pairs(a) do S.same(v, b[k], path .. "." .. tostring(k)) end
  for k in pairs(b) do if a[k] == nil then fail(path .. "." .. tostring(k) .. " unexpected") end end
end

function S.run()
  local failed = 0
  io.stdout:write(("TAP version 13\n1..%d\n"):format(#S.cases))
  for i, c in ipairs(S.cases) do
    local okay, e = xpcall(c.fn, function(err)
      if type(err) == "table" and err.spec then return err.msg end
      return debug.traceback(tostring(err), 2)
    end)
    if okay then
      io.stdout:write(("ok %d - %s\n"):format(i, c.name))
    else
      failed = failed + 1
      io.stdout:write(("not ok %d - %s\n"):format(i, c.name))
      for line in tostring(e):gmatch("[^\n]+") do io.stdout:write("# ", line, "\n") end
    end
  end
  io.stdout:write(("# %d passed, %d failed\n"):format(#S.cases - failed, failed))
  if failed > 0 then os.exit(1) end
end

return S
