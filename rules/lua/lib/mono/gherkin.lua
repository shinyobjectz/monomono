--- Gherkin, parsed into pickles: { feature, path, scenarios = { { name, tags, steps = { { keyword, text, doc, table } } } } }
--- Handles Feature, Background, Scenario, Scenario Outline + Examples, Given/When/Then/And/But, """docstrings""", | tables |.
local G = {}

local KEYWORDS = { Given = "given", When = "when", Then = "then", And = "and", But = "but", ["*"] = "and" }

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function parse_table_row(line)
  local cells = {}
  line = trim(line):gsub("|%s*$", "")   -- drop the closing bar
  for cell in line:gmatch("|([^|]*)") do cells[#cells + 1] = trim(cell) end
  return cells
end

function G.parse(text, path)
  local doc = { feature = "", path = path or "", scenarios = {}, background = {} }
  local lines = {}
  for l in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = l end
  local i, n = 1, #lines
  local current, steps, tags, outline, examples = nil, nil, {}, nil, nil
  local last_kw = "given"

  local function finish()
    if not current then return end
    if outline and examples and #examples > 0 then
      local header = examples[1]
      for r = 2, #examples do
        local row = examples[r]
        local sc = { name = current.name .. " (" .. table.concat(row, ", ") .. ")", tags = current.tags, steps = {}, line = current.line }
        for _, st in ipairs(current.steps) do
          local t = st.text
          for c = 1, #header do
            local key = "<" .. (header[c]:gsub("%p", "%%%0")) .. ">"
            local val = (row[c] or ""):gsub("%%", "%%%%")
            t = t:gsub(key, val)
          end
          sc.steps[#sc.steps + 1] = { keyword = st.keyword, text = t, doc = st.doc, table = st.table, line = st.line }
        end
        doc.scenarios[#doc.scenarios + 1] = sc
      end
    else
      doc.scenarios[#doc.scenarios + 1] = current
    end
    current, outline, examples = nil, nil, nil
  end

  while i <= n do
    local raw = lines[i]
    local line = trim(raw)
    if line == "" or line:sub(1, 1) == "#" then
      i = i + 1
    elseif line:sub(1, 1) == "@" then
      for t in line:gmatch("@(%S+)") do tags[#tags + 1] = t end
      i = i + 1
    elseif line:match("^Feature:") then
      doc.feature = trim(line:sub(9)); tags = {}; i = i + 1
    elseif line:match("^Background:") then
      finish(); steps = doc.background; last_kw = "given"; i = i + 1
    elseif line:match("^Scenario Outline:") or line:match("^Scenario Template:") then
      finish()
      current = { name = trim(line:gsub("^Scenario %a+:", "")), tags = tags, steps = {}, line = i }
      for _, b in ipairs(doc.background) do current.steps[#current.steps + 1] = b end
      steps = current.steps; outline = true; tags = {}; last_kw = "given"; i = i + 1
    elseif line:match("^Scenario:") or line:match("^Example:") then
      finish()
      current = { name = trim(line:gsub("^%a+:", "")), tags = tags, steps = {}, line = i }
      for _, b in ipairs(doc.background) do current.steps[#current.steps + 1] = b end
      steps = current.steps; tags = {}; last_kw = "given"; i = i + 1
    elseif line:match("^Examples:") or line:match("^Scenarios:") then
      examples = {}; i = i + 1
      while i <= n and trim(lines[i]):sub(1, 1) == "|" do examples[#examples + 1] = parse_table_row(trim(lines[i])); i = i + 1 end
    else
      local kwtext, rest = line:match("^(%a+)%s+(.*)$")
      if not kwtext then kwtext, rest = line:match("^(%*)%s+(.*)$") end
      local kw = kwtext and KEYWORDS[kwtext]
      if kw and steps then
        if kw == "and" or kw == "but" then kw = last_kw else last_kw = kw end
        local st = { keyword = kw, text = trim(rest), line = i }
        i = i + 1
        if i <= n and trim(lines[i]):match('^"""') then
          local buf = {}
          i = i + 1
          while i <= n and not trim(lines[i]):match('^"""') do buf[#buf + 1] = lines[i]; i = i + 1 end
          i = i + 1
          -- strip common indent
          local indent
          for _, b in ipairs(buf) do local ws = b:match("^(%s*)%S"); if ws and (not indent or #ws < #indent) then indent = ws end end
          for k, b in ipairs(buf) do buf[k] = indent and b:sub(#indent + 1) or b end
          st.doc = table.concat(buf, "\n")
        elseif i <= n and trim(lines[i]):sub(1, 1) == "|" then
          st.table = {}
          while i <= n and trim(lines[i]):sub(1, 1) == "|" do st.table[#st.table + 1] = parse_table_row(trim(lines[i])); i = i + 1 end
        end
        steps[#steps + 1] = st
      else
        i = i + 1  -- prose under a Feature or Scenario
      end
    end
  end
  finish()
  return doc
end

function G.read(path)
  local f = assert(io.open(path, "r"))
  local s = f:read("*a")
  f:close()
  return G.parse(s, path)
end

--- Step skeletons for every sentence a steps file does not yet bind: what to paste into test/steps.lua.
function G.skeletons(doc, bound)
  local out, seen = {}, {}
  for _, sc in ipairs(doc.scenarios) do
    for _, st in ipairs(sc.steps) do
      local key = st.keyword .. " " .. st.text
      if not seen[key] and not (bound and bound(st.keyword, st.text)) then
        seen[key] = true
        local expr = st.text:gsub('"[^"]*"', "{string}"):gsub("%f[%d]%-?%d+%f[%D]", "{int}")
        out[#out + 1] = string.format('steps.%s(%q, function(ctx%s)\n  error("pending: %s")\nend)', st.keyword, expr,
          expr:find("{") and ", ..." or "", st.text:gsub('"', "'"))
      end
    end
  end
  return table.concat(out, "\n\n") .. (#out > 0 and "\n" or "")
end

return G
