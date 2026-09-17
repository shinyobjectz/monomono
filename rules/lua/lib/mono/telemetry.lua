--- Telemetry: spans with a closed vocabulary, rendered as OTLP JSON, a tree, or Gherkin.
---
--- A span is { id, parent, name, at, ms, ok, attrs }. `attrs` never carries a payload:
--- every key is in the vocabulary or `close_span` refuses it. The vocabulary is small by
--- default (OpenTelemetry GenAI names plus monomono's own) and a consumer extends or renames
--- it with `vocabulary(profile)`, so an app's collector sees its own names, not this package's.
---
--- A profile is { adopted = {names...}, minted = {name = rule...}, names = {feature=, scenario=,
--- step=, outcome=, undefined=, unclosed=, run=, kind=, keyword=, scenarios=, steps=, passed=, failed=},
--- events = function(event) -> name, attrs, ok }. Every key the runner writes is in `names`, so a
--- profile that renames them all leaves no monomono.* key in the trace; a partial `names` keeps
--- the defaults for the rest. A renamed attribute must also be minted, or the recorder refuses it.
--- The feature runner loads MONO_TELEMETRY_PROFILE (a module name) before any span opens; a steps
--- file may call vocabulary() itself. This module opens no socket and requires nothing.
local T = {}

T.VOCABULARY = 1

--- OpenTelemetry GenAI semantic-convention names, verbatim.
T.ADOPTED = {
  "gen_ai.operation.name", "gen_ai.provider.name", "gen_ai.agent.name",
  "gen_ai.request.model", "gen_ai.response.model",
  "gen_ai.usage.input_tokens", "gen_ai.usage.output_tokens",
  "gen_ai.tool.name", "gen_ai.tool.call.id",
}

--- What a build graph and a feature runner say about themselves.
T.MINTED = {
  ["monomono.keyword"]   = { "given", "when", "then" },
  ["monomono.scenarios"] = "number",
  ["monomono.steps"]     = "number",
  ["monomono.passed"]    = "number",
  ["monomono.failed"]    = "number",
  ["monomono.undefined"] = "number",
  ["monomono.outcome"]   = { "passed", "failed", "undefined", "broken", "skipped" },
  ["monomono.unclosed"]  = "boolean",
  ["monomono.kind"]      = "string",
}

--- Span and attribute names the runner uses; a profile renames them (a scenario may be an app's join span).
--- The runner writes no attribute key that is not listed here.
T.names = {
  feature = "monomono.feature", scenario = "monomono.scenario", step = "monomono.step",
  outcome = "monomono.outcome", undefined = "monomono.undefined", unclosed = "monomono.unclosed",
  run = "monomono.run", kind = "monomono.kind", keyword = "monomono.keyword",
  scenarios = "monomono.scenarios", steps = "monomono.steps", passed = "monomono.passed", failed = "monomono.failed",
}

T.events = nil   -- a profile's mapping from an app's flat run events to spans

--- Extend or rename the vocabulary. Adopted names are appended, minted rules merged, names overridden.
function T.vocabulary(profile)
  for _, n in ipairs(profile.adopted or {}) do T.ADOPTED[#T.ADOPTED + 1] = n end
  for k, rule in pairs(profile.minted or {}) do T.MINTED[k] = rule end
  for k, v in pairs(profile.names or {}) do T.names[k] = v end
  if profile.events then T.events = profile.events end
  if profile.version then T.VOCABULARY = profile.version end
  return T
end

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
  if closed == "number" or closed == "boolean" or closed == "string" then
    if type(value) == closed then return true end
    return false, string.format("%s is a %s, and this is a %s", name, closed, type(value))
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

--- A recorder: open_span / close_span / close_all. `clock()` returns milliseconds.
--- `spans` is the authoritative list, in open order.
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
    for _, s in pairs(R.open) do R.close_span(s, { [T.names.unclosed] = true }, false) end
  end
  return R
end

-- rendering: OTLP/JSON as a collector expects it, keys sorted, ids deterministic
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

local function short(key)
  return (key:gsub("^[%w_]+%.", ""))
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
      marks[#marks + 1] = short(key) .. "=" .. tostring(s.attrs[key])
    end
    out[#out + 1] = string.format("%s%s%s  %dms%s", string.rep("  ", depth), s.ok == false and "! " or "", s.name, s.ms or 0, #marks > 0 and ("  " .. table.concat(marks, " ")) or "")
    for _, c in ipairs(kids[s.id] or {}) do walk(c, depth + 1) end
  end
  for _, r in ipairs(roots) do walk(r, 0) end
  if #out == 0 then return "(no spans)\n" end
  return table.concat(out, "\n") .. "\n"
end

local function strip(name, prefix)
  if name:sub(1, #prefix + 1) == prefix .. " " then return name:sub(#prefix + 2) end
  return nil
end

--- The other direction: a trace is read back out AS a scenario.
--- Scenario spans become `Scenario:` lines, step spans become their sentences, outcomes become tags.
function T.observe(spans)
  local N = T.names
  local kids, roots = {}, {}
  for _, s in ipairs(spans) do
    if s.parent then kids[s.parent] = kids[s.parent] or {}; table.insert(kids[s.parent], s) else roots[#roots + 1] = s end
  end
  local out = {}
  local function scenario(c)
    local name = strip(c.name, N.scenario)
    if not name then return end
    local outcome = c.attrs and c.attrs[N.outcome]
    if outcome then out[#out + 1] = "@" .. outcome end
    out[#out + 1] = "Scenario: " .. name
    for _, st in ipairs(kids[c.id] or {}) do
      local text = strip(st.name, N.step)
      if text then
        local kw = st.attrs and st.attrs[N.keyword] or "and"
        out[#out + 1] = "  " .. (kw:sub(1, 1):upper() .. kw:sub(2)) .. " " .. text
      end
    end
    out[#out + 1] = ""
  end
  for _, r in ipairs(roots) do
    local path = strip(r.name, N.feature)
    if path then
      out[#out + 1] = "# from " .. path
      for _, c in ipairs(kids[r.id] or {}) do scenario(c) end
    else
      scenario(r)   -- a scenario span at the root, without a feature above it
    end
  end
  return table.concat(out, "\n") .. "\n"
end

--- An app's flat run events as spans under one run span, one per event, so a machine trace and
--- an agent trace land in one collector. The profile's `events(e)` returns name, attrs, ok;
--- without a profile an event is { kind, thing } and is ok unless kind is "error".
function T.from_events(events, clock)
  local R = T.recorder(clock)
  local root = R.open_span(T.names.run, nil, {})
  for _, e in ipairs(events) do
    local name, attrs, ok
    if T.events then
      name, attrs, ok = T.events(e)
    else
      name = tostring(e.kind) .. (e.thing and (" " .. tostring(e.thing)) or "")
      attrs = { [T.names.kind] = tostring(e.kind) }
      ok = e.kind ~= "error"
    end
    local s = R.open_span(name, root, attrs or {})
    R.close_span(s, {}, ok ~= false)
  end
  R.close_span(root, {}, true)
  return R.spans
end

return T
