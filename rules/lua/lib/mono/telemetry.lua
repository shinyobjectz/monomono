--- Telemetry: spans in malleable's shape, malleable's closed vocabulary, OTLP out.
---
--- A span is { id, parent, name, at, ms, ok, attrs }. `attrs` never carries a payload
--- (malleable rule 8): every key is in the vocabulary below or `close_span` refuses it.
--- The scenario is the join: `malleable.scenario {name}` roots a Gherkin run, so a
--- collector trace is attributable to the sentence in the feature file.
---
--- Compatible with malleable's `trace.lua` (VOCABULARY 1) and typeaway's TraceSpan.
--- This module opens no socket and requires nothing; transport is the host's.
local T = {}

T.VOCABULARY = 1

--- OpenTelemetry GenAI names, verbatim (as malleable adopts them).
T.ADOPTED = {
  "gen_ai.operation.name", "gen_ai.provider.name", "gen_ai.agent.name",
  "gen_ai.request.model", "gen_ai.response.model",
  "gen_ai.usage.input_tokens", "gen_ai.usage.output_tokens",
  "gen_ai.tool.name", "gen_ai.tool.call.id",
}

--- malleable's minted names, verbatim, plus monomono's own under its prefix.
T.MINTED = {
  ["malleable.stop"]          = { "answered", "budget", "refused", "error" },
  ["malleable.steps"]         = "number",
  ["malleable.budget"]        = "number",
  ["malleable.calls"]         = "number",
  ["malleable.tools"]         = "number",
  ["malleable.cached_tokens"] = "number",
  ["malleable.skills"]        = "number",
  ["malleable.act"]           = { set = { "builds", "commits", "connects", "deletes", "escalates", "inspects",
                                          "installs", "publishes", "reads", "tests", "writes" } },
  ["malleable.unplaced"]      = "number",
  ["malleable.notes"]         = "number",
  ["malleable.depth"]         = "number",
  ["malleable.gate.answer"]   = { "allowed", "edited", "refused", "stopped", "absent" },
  ["malleable.refused_by"]    = { "gate", "hook", "error" },
  ["malleable.requirement"]   = { "unmet" },
  ["malleable.unclosed"]      = "boolean",
  ["malleable.dropped"]       = "number",
  ["malleable.outcome"]       = { "passed", "failed", "undefined", "broken", "skipped" },
  ["malleable.undefined"]     = "number",
  ["malleable.samples"]       = "number",
  ["malleable.rate"]          = "number",
  -- monomono: what a build graph and a feature runner have that an agent harness does not
  ["monomono.keyword"]        = { "given", "when", "then" },
  ["monomono.scenarios"]      = "number",
  ["monomono.steps"]          = "number",
  ["monomono.passed"]         = "number",
  ["monomono.failed"]         = "number",
  ["monomono.kind"]           = { "start", "call", "when", "refused", "error", "stop", "halt" },
}

function T.attributes()
  local out = {}
  for i = 1, #T.ADOPTED do out[T.ADOPTED[i]] = true end
  for k in pairs(T.MINTED) do out[k] = true end
  return out
end

--- Is this attribute a value the vocabulary allows? false and a sentence when not.
function T.allowed(name, value)
  local closed = T.MINTED[name]
  if closed == nil then
    for i = 1, #T.ADOPTED do if T.ADOPTED[i] == name then return true end end
    return false, string.format("%q is not in the vocabulary", name)
  end
  if closed == "number" then
    if type(value) == "number" then return true end
    return false, string.format("%s is a number, and this is a %s", name, type(value))
  end
  if closed == "boolean" then
    if type(value) == "boolean" then return true end
    return false, string.format("%s is a boolean, and this is a %s", name, type(value))
  end
  if type(closed.set) == "table" then
    if type(value) ~= "string" or value == "" then return false, name .. " is a comma-joined set of terms" end
    local known = {}
    for i = 1, #closed.set do known[closed.set[i]] = true end
    for term in (value .. ", "):gmatch("(.-), ") do
      if not known[term] then return false, string.format("%s draws from %s, and this says %q", name, table.concat(closed.set, ", "), term) end
    end
    return true
  end
  for i = 1, #closed do if value == closed[i] then return true end end
  return false, string.format("%s is one of %s, and this is %q", name, table.concat(closed, ", "), tostring(value))
end

--- A recorder: open_span / close_span / close_all, the same surface as malleable's turn.recorder.
--- `clock()` returns milliseconds. `spans` is the authoritative list, in open order.
function T.recorder(clock)
  if not clock then
    local osclock = (type(os) == "table") and os.clock or nil
    local tick = 0
    clock = osclock and function() return math.floor(osclock() * 1000) end or function() tick = tick + 1; return tick end
  end
  local R = { spans = {}, open = {}, next_id = 0 }
  function R.open_span(name, parent, attrs)
    R.next_id = R.next_id + 1
    local s = { id = tostring(R.next_id), parent = parent and parent.id or nil, name = name, at = clock(), ms = 0, ok = true, attrs = {} }
    for k, v in pairs(attrs or {}) do
      local okay, why = T.allowed(k, v)
      if not okay then error("telemetry: " .. why, 2) end
      s.attrs[k] = v
    end
    R.spans[#R.spans + 1] = s
    R.open[s.id] = s
    return s
  end
  function R.close_span(s, attrs, ok)
    for k, v in pairs(attrs or {}) do
      local okay, why = T.allowed(k, v)
      if not okay then error("telemetry: " .. why, 2) end
      s.attrs[k] = v
    end
    s.ms = clock() - s.at
    if ok ~= nil then s.ok = ok end
    R.open[s.id] = nil
    return s
  end
  function R.close_all()
    for _, s in pairs(R.open) do R.close_span(s, { ["malleable.unclosed"] = true }, false) end
  end
  return R
end

-- rendering (byte-for-byte the shape malleable's trace.otlp writes)
local function esc(s)
  s = tostring(s)
  s = s:gsub("\\", "\\\\"):gsub('"', '\\"')
  s = s:gsub("[%z\1-\31]", function(c) return string.format("\\u%04x", string.byte(c)) end)
  return s
end
local function attr_value(v)
  if type(v) == "number" then
    if v == math.floor(v) and math.abs(v) < 2 ^ 53 then return string.format('{"intValue":"%d"}', v) end
    return string.format('{"doubleValue":%.17g}', v)
  end
  if type(v) == "boolean" then return string.format('{"boolValue":%s}', tostring(v)) end
  return string.format('{"stringValue":"%s"}', esc(v))
end
local function sorted_keys(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = k end
  table.sort(out)
  return out
end

--- The trace as one OTLP JSON document. ids = { trace = hex32, span = fn(id) -> hex16, service = name, scope = name }.
function T.otlp(spans, ids)
  ids = ids or {}
  local trace_id = ids.trace or string.rep("0", 32)
  local span_id = ids.span or function(id) return string.format("%016x", tonumber(id) or 0) end
  local service = ids.service or "monomono"
  local scope = ids.scope or "monomono"
  local out = {}
  for i = 1, #spans do
    local s = spans[i]
    local attrs = {}
    local keys = sorted_keys(s.attrs or {})
    for k = 1, #keys do
      attrs[#attrs + 1] = string.format('{"key":"%s","value":%s}', esc(keys[k]), attr_value(s.attrs[keys[k]]))
    end
    local start_ns = string.format("%d000000", s.at or 0)
    local end_ns = string.format("%d000000", (s.at or 0) + (s.ms or 0))
    out[#out + 1] = string.format(
      '{"traceId":"%s","spanId":"%s",%s"name":"%s","kind":1,"startTimeUnixNano":"%s","endTimeUnixNano":"%s","attributes":[%s],"status":{"code":%d}}',
      trace_id, span_id(s.id), s.parent and string.format('"parentSpanId":"%s",', span_id(s.parent)) or "",
      esc(s.name), start_ns, end_ns, table.concat(attrs, ","), s.ok == false and 2 or 1)
  end
  return string.format(
    '{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"%s"}}]},"scopeSpans":[{"scope":{"name":"%s","version":"%d"},"spans":[%s]}]}]}',
    esc(service), esc(scope), T.VOCABULARY, table.concat(out, ","))
end

--- The trace as an indented tree, for a person at a terminal.
function T.render(spans)
  local kids, roots = {}, {}
  for i = 1, #spans do
    local s = spans[i]
    if s.parent then kids[s.parent] = kids[s.parent] or {}; table.insert(kids[s.parent], s) else roots[#roots + 1] = s end
  end
  local out = {}
  local function walk(s, depth)
    local marks = {}
    for _, key in ipairs(sorted_keys(s.attrs or {})) do
      marks[#marks + 1] = key:gsub("^malleable%.", ""):gsub("^gen_ai%.", ""):gsub("^monomono%.", "") .. "=" .. tostring(s.attrs[key])
    end
    out[#out + 1] = string.format("%s%s%s  %dms%s", string.rep("  ", depth), s.ok == false and "! " or "", s.name, s.ms or 0, #marks > 0 and ("  " .. table.concat(marks, " ")) or "")
    for _, c in ipairs(kids[s.id] or {}) do walk(c, depth + 1) end
  end
  for _, r in ipairs(roots) do walk(r, 0) end
  if #out == 0 then return "(no spans)\n" end
  return table.concat(out, "\n") .. "\n"
end

--- The other direction, as malleable rules it: a trace is read back out AS a scenario.
--- Scenario spans become `Scenario:` lines, step spans become their sentences, outcomes become tags.
function T.observe(spans)
  local kids, roots = {}, {}
  for _, s in ipairs(spans) do
    if s.parent then kids[s.parent] = kids[s.parent] or {}; table.insert(kids[s.parent], s) else roots[#roots + 1] = s end
  end
  local out = {}
  local function feature(s)
    local path = s.name:match("^monomono%.feature (.*)$")
    if path then out[#out + 1] = "# from " .. path end
    for _, c in ipairs(kids[s.id] or {}) do
      local name = c.name:match("^malleable%.scenario (.*)$")
      if name then
        local outcome = c.attrs and c.attrs["malleable.outcome"]
        if outcome then out[#out + 1] = "@" .. outcome end
        out[#out + 1] = "Scenario: " .. name
        for _, st in ipairs(kids[c.id] or {}) do
          local text = st.name:match("^monomono%.step (.*)$")
          if text then
            local kw = st.attrs and st.attrs["monomono.keyword"] or "and"
            out[#out + 1] = "  " .. (kw:sub(1, 1):upper() .. kw:sub(2)) .. " " .. text
          end
        end
        out[#out + 1] = ""
      end
    end
  end
  for _, r in ipairs(roots) do
    if r.name:match("^monomono%.feature ") then feature(r)
    elseif r.name:match("^malleable%.scenario ") then feature({ id = "", name = "", kids = nil }); end
  end
  -- scenario spans at the root, without a feature span above them
  for _, r in ipairs(roots) do
    local name = r.name:match("^malleable%.scenario (.*)$")
    if name then
      local fake = { id = "__root", name = "" }
      kids[fake.id] = { r }
      feature(fake)
    end
  end
  return table.concat(out, "\n") .. "\n"
end

--- typeaway's flat run events ({kind, thing, ...}, docs/EXECUTION.md) as spans, one per event,
--- so a machine trace and an agent trace land in one collector.
function T.from_events(events, clock)
  local R = T.recorder(clock)
  local root = R.open_span("monomono.run", nil, {})
  for _, e in ipairs(events) do
    local name = tostring(e.kind) .. (e.thing and (" " .. tostring(e.thing)) or (e.from and (" " .. tostring(e.from)) or ""))
    local s = R.open_span(name, root, { ["monomono.kind"] = e.kind })
    local ok = not (e.kind == "refused" or e.kind == "error" or e.kind == "halt")
    R.close_span(s, {}, ok)
  end
  R.close_span(root, {}, true)
  return R.spans
end

return T
