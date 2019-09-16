//
//  InfBase.swift
//  SwiftyLua
//
//  Created by Zhao Han on 9/9/18.
//  Copyright © 2018 hanzhao. All rights reserved.
//

import Foundation

@objc class InfBase: NSObject {
    var target: ObjectForwarder?
    
    override public func forwardingTarget(for sel: Selector!) -> Any? {
        print("forwarding \(self), \(String(describing: sel))")
        let is_meta = class_isMetaClass(object_getClass(self))
        
        if is_meta {
            return ClassForwarder(LuaClass.L, class: type(of: self))
        } else {
            return target
        }
    }
    
    override public func responds(to sel: Selector!) -> Bool {
        let L = LuaClass.L!
        let class_name = object_getClassName(self)
        lua_getglobal(L, class_name)
        assert(lua_type(L, -1) == LUA_TTABLE); // class
        
        let method_name = NSStringFromSelector(sel)
        
        // convert to lua function name
        let lua_method_name = method_name.replacingOccurrences(of: ":", with: "_")
        lua_getfield(L, -1, lua_method_name) // class, method
        let rslt = (lua_type(L, -1) == LUA_TFUNCTION)
        lua_pop(L, 2)
        
        print("response to: \(NSStringFromSelector(sel)) -> \(rslt))")
        
        return rslt
    }
    
    deinit {
        let L = LuaClass.L!
        
        print("deallocating: \(self) \(hex(self))")
        
        lua_getglobal(L, "__cross_reg")
        print_stack(L, "get __cross_reg")
        lua_pop(L, 1)
        
        // remove from strong map?
        // ...
    }
}
