-- skeletons.lua [STEPS.lua|""] FEATURE...  — step skeletons for every sentence the steps file does not bind
local G = require("mono.gherkin")
local S = require("mono.steps")
local steps_file = table.remove(arg, 1)
if steps_file and steps_file ~= "" then
  local f = loadfile(steps_file)
  if f then f(S) end
end
local out = {}
for _, path in ipairs(arg) do out[#out + 1] = G.skeletons(G.read(path), S.bound) end
io.write(table.concat(out))
