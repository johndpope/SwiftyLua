print('in playground, env is: ', _ENV, '_G is: ', _G)

function class_creation()
	--[[
	local my_cls = class {'MyClass', 'NSObject', {'HelloProtocol'}}
	print('created class', my_cls, MyClass)
	print_tbl(MyClass, 'registered my class')
	--]]
end

function play()
	local obj = Foo:init_hp(21)
	print('Foo ctored', obj)
	-- obj:desc()

	-- obj:talk(1, 'yeah! from Lua')

	local bar = Bar:init()
	print('Bar ctored', bar)
	obj:talk_with(bar)
	
	local ret_bar = obj:the_bar_opt()
	print('ret_bar is', ret_bar)
	assert(ret_bar == bar)
	assert(rawequal(ret_bar, bar))

	assert(obj:hp() == 21)
	obj:desc()

	-- obj = Foo:init()
	obj:talk(1, 'yeah! from Lua')

	obj:talk_with(Bar:init())
	obj:talk_with(nil)

	obj:talk_with_sbar_opt(SBar:init('hi opt'))

	local sbar = SBar:init("hey jude!")
	print('sbar is: ', sbar)

	-- print('before change', sbar:message())
	sbar:change('lua said structure')
	print('after change', sbar:message())
	obj:talk_with_s(sbar)
	
	local ret_sbar = obj:the_sbar()
	print('returned sbar: ', ret_sbar)
	
	local ret_sbar_opt = obj:the_sbar_opt()
	assert(type(ret_sbar_opt) == 'table')
	
	obj:talk_with_sbar_opt(nil)
	assert(obj:the_sbar_opt() == nil)
	
	local arr = obj:iarr()
	print('arr is: ', arr)
	for k, v in pairs(arr) do
		print(k, v)
	end
	
	print_swift_reg()
end

play()
collectgarbage()
print('after play')
class_creation()
print_swift_reg()
