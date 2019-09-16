print('hello from swifty lua')

local script_path = ...
package.path = package.path .. ';' .. script_path .. '?.lua'

require 'env'
require 'playground'
require 'myclass'