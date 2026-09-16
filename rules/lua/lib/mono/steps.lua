--- Step definitions for Gherkin features, with malleable's expression placeholders:
---   {int} {float} {word} {string} {value}
---   local steps = require("mono.steps")
---   steps.given("the budget is {int}", function(ctx, n) ctx.budget = n end)
---   steps.when("the agent is asked {string}", function(ctx, q) ... end)
---   steps.then("it takes {int} steps", function(ctx, n) assert(ctx.steps == n) end)
local S = { defs = {} }

local PLACEHOLDERS = {
  ["{int}"] = { "(%-?%d+)", tonumber },
  ["{float}"] = { "(%-?%d+%.?%d*)", tonumber },
  ["{word}"] = { "(%S+)", tostring },
  ["{string}"] = { '"([^"]*)"', tostring },
  ["{value}"] = { "(.+)", tostring },
}

local function compile(expr)
  local casts = {}
  local pat = expr:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")   -- escape magic chars
  pat = pat:gsub("%{(%a+)%}", function(name)
    local ph = PLACEHOLDERS["{" .. name .. "}"]
    if not ph then error("unknown placeholder {" .. name .. "} in step " .. expr, 3) end
    casts[#casts + 1] = ph[2]
    return ph[1]
  end)
  return "^" .. pat .. "$", casts
end

local function define(keyword, expr, fn)
  local pat, casts = compile(expr)
  S.defs[#S.defs + 1] = { keyword = keyword, expr = expr, pattern = pat, casts = casts, fn = fn }
end

function S.given(expr, fn) define("given", expr, fn) end
function S.when(expr, fn) define("when", expr, fn) end
S["then"] = function(expr, fn) define("then", expr, fn) end
function S.step(expr, fn) define(nil, expr, fn) end   -- any keyword

--- Find the definition for a sentence: returns def, {captured args} or nil.
function S.find(keyword, text)
  for _, d in ipairs(S.defs) do
    if d.keyword == nil or d.keyword == keyword then
      if #d.casts == 0 then
        if text:match(d.pattern) then return d, {} end
      else
        local caps = { text:match(d.pattern) }
        if #caps > 0 then
          for i, c in ipairs(caps) do caps[i] = d.casts[i](c) end
          return d, caps
        end
      end
    end
  end
  return nil
end

function S.bound(keyword, text) return S.find(keyword, text) ~= nil end

return S
