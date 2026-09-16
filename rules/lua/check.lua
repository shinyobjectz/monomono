-- check.lua FILE  — compile only; works on every interpreter, unlike luac -p
local f, err = loadfile(arg[1])
if not f then io.stderr:write(err, "\n") os.exit(1) end
