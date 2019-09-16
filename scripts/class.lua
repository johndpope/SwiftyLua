function class(tbl)
	local name = tbl[1]
	local base = tbl[2]
	local protocols = tbl[3] or {}
	
	local meta = LuaClass:init(name, base, protocols)
	
	local l_class = _G[name]
	setmetatable(l_class, {__index = _G})
	
	-- debug.setupvalue(class, 1, l_class)
	
	return l_class
end