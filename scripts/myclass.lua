_ENV = class {'MyClass', 'NSObject', {'HelloProtocol'}}

function init(self)
	print('call init -> __ctor ', self)
	local obj = self.__ctor()
	print('return ', obj)
	return obj
end

function create(self)
	print_tbl(self, 'create:')
	return self:init()
end

function hello(self)
	print('hello xxx from: ', self)
end

--[[
local obj = MyClass:init()
print('my class init', obj)
obj:hello()
--]]
