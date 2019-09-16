
-- keep userdata mapping with lua table
-- __swift_reg = {}
-- setmetatable(__swift_reg, { __mode = 'v' })

-- print with [lua] prefix
print = (function ()
	local orig_print = print
	return function (...)
		local rslt = "[lua] "
		for i, v in ipairs {...} do
		   rslt = rslt .. tostring(v) .. "\t"
		end
		orig_print(rslt)
	end
end)()

function print_swift_reg()
	print('__swift_reg is: {')
	for k, v in pairs(__swift_reg) do
		local meta = getmetatable(v)
		print(' ', k, '=', v, meta.__name)
	end
	print('}')
end

function print_tbl(tbl, msg) 
	print(('---' .. msg .. '--- {') or '--- {')
	for k, v in pairs(tbl) do
		print(tostring(k), tostring(v))
	end
	print('} --- end ---')
end

require('class')

print('env is ready')