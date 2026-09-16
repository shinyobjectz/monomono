-- features.lua STEPS.lua FEATURE.feature...   (the lua_feature_test entry point)
-- Runs every scenario against the step definitions, prints TAP, and records one span tree:
--   monomono.feature <path> > malleable.scenario <name> > monomono.step <text>
-- MONO_TRACE_OUT=<file> writes OTLP JSON. MONO_TRACE=1 prints the tree. MONO_OBSERVE=1 prints the trace read back as Gherkin.
local telemetry = require("mono.telemetry")
local gherkin = require("mono.gherkin")
local steps = require("mono.steps")

if arg[1] == "--steps" then table.remove(arg, 1) end
local steps_file = table.remove(arg, 1)
if not steps_file then io.stderr:write("usage: features.lua [--steps] STEPS.lua FEATURE...\n") os.exit(2) end
local chunk = assert(loadfile(steps_file))
chunk(steps)   -- a steps file may `return` nothing; it registers through require("mono.steps")

local R = telemetry.recorder(function() return math.floor(os.clock() * 1000) end)
local total, failed, undefined, idx = 0, 0, 0, 0
local out = {}
local report = {}   -- machine-readable: one row per scenario (MONO_REPORT_OUT)

for _, path in ipairs(arg) do
  local doc = gherkin.read(path)
  local fspan = R.open_span("monomono.feature " .. path, nil, { ["monomono.scenarios"] = #doc.scenarios })
  local fpassed, ffailed = 0, 0
  for _, sc in ipairs(doc.scenarios) do
    total = total + 1; idx = idx + 1
    local span = R.open_span("malleable.scenario " .. sc.name, fspan, { ["monomono.steps"] = #sc.steps })
    local ctx = { scenario = sc.name, feature = doc.feature }
    local outcome, why, at = "passed", nil, nil
    for _, st in ipairs(sc.steps) do
      local s = R.open_span("monomono.step " .. st.text, span, { ["monomono.keyword"] = st.keyword })
      if outcome ~= "passed" then
        R.close_span(s, { ["malleable.outcome"] = "skipped" }, true)
      else
        local def, caps = steps.find(st.keyword, st.text)
        if not def then
          outcome, why, at = "undefined", "no step matches: " .. st.keyword .. " " .. st.text, st
          R.close_span(s, { ["malleable.outcome"] = "undefined" }, false)
        else
          local okay, err = xpcall(function() return def.fn(ctx, (table.unpack or unpack)(caps), st.doc, st.table) end, debug.traceback)
          if okay then
            R.close_span(s, { ["malleable.outcome"] = "passed" }, true)
          else
            outcome, why, at = "failed", tostring(err), st
            R.close_span(s, { ["malleable.outcome"] = "failed" }, false)
          end
        end
      end
    end
    R.close_span(span, { ["malleable.outcome"] = outcome }, outcome == "passed")
    report[#report + 1] = { feature = path, line = sc.line, scenario = sc.name, outcome = outcome,
      step = at and { keyword = at.keyword, text = at.text, line = at.line } or nil, message = why }
    if outcome == "passed" then
      fpassed = fpassed + 1
      out[#out + 1] = ("ok %d - %s"):format(idx, sc.name)
    else
      ffailed = ffailed + 1
      if outcome == "undefined" then undefined = undefined + 1 else failed = failed + 1 end
      out[#out + 1] = ("not ok %d - %s"):format(idx, sc.name)
      for line in tostring(why):gmatch("[^\n]+") do out[#out + 1] = "# " .. line end
    end
  end
  R.close_span(fspan, { ["monomono.passed"] = fpassed, ["monomono.failed"] = ffailed, ["malleable.undefined"] = undefined }, ffailed == 0)
end
R.close_all()

io.stdout:write("TAP version 13\n1..", total, "\n", table.concat(out, "\n"), "\n")
io.stdout:write(("# %d passed, %d failed, %d undefined\n"):format(total - failed - undefined, failed, undefined))
if os.getenv("MONO_REPORT_OUT") then
  local function j(s) return '"' .. tostring(s):gsub("[\\\"]", "\\%0"):gsub("\n", "\\n") .. '"' end
  local rows = {}
  for _, r in ipairs(report) do
    rows[#rows + 1] = ("{\"feature\":%s,\"line\":%d,\"scenario\":%s,\"outcome\":%s%s%s}"):format(
      j(r.feature), r.line or 0, j(r.scenario), j(r.outcome),
      r.step and (",\"step\":{\"keyword\":%s,\"text\":%s,\"line\":%d}"):format(j(r.step.keyword), j(r.step.text), r.step.line or 0) or "",
      r.message and (",\"message\":" .. j(r.message)) or "")
  end
  local f = assert(io.open(os.getenv("MONO_REPORT_OUT"), "w"))
  f:write(("{\"passed\":%d,\"failed\":%d,\"undefined\":%d,\"scenarios\":[%s]}\n"):format(total - failed - undefined, failed, undefined, table.concat(rows, ",")))
  f:close()
end
if os.getenv("MONO_TRACE_OUT") then
  local f = assert(io.open(os.getenv("MONO_TRACE_OUT"), "w"))
  f:write(telemetry.otlp(R.spans, { service = os.getenv("MONO_SERVICE") or "monomono" }))
  f:close()
end
if os.getenv("MONO_TRACE") then io.stderr:write(telemetry.render(R.spans)) end
if os.getenv("MONO_OBSERVE") then io.stderr:write(telemetry.observe(R.spans)) end
if failed + undefined > 0 then os.exit(1) end
