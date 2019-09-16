//
//  Expose.swift
//  SwiftyLua
//
//  Created by hanzhao on 2017/7/13.
//  Copyright © 2017年 hanzhao. All rights reserved.
//

import Foundation
import LuaSource
import ObjectiveC.runtime

private let print = Logger.genPrint(level: .expose)

extension luaL_Reg {
    static func create(_ c_name: String, _ f: @escaping lua_CFunction) -> luaL_Reg {
        return luaL_Reg(name: (c_name as NSString).utf8String!, func: f)
    }
}

private let reg = luaL_Reg.create
private let null = luaL_Reg()

let s_print_stack: @convention(c) (L_STATE?) -> Int32 = { L in
    print_stack(L!)
    return 0
}

let s_hello: @convention(c) (L_STATE?) -> Int32 = {L in
    print("hello from lua -> swift")

    return 0
}

// class[k] = func
let s_add_protocol_method: @convention(c) (L_STATE?) -> Int32 = {L in
    print_stack(L!, "add protocol method")

    lua_pushstring(L, "__name")
    lua_rawget(L, 1)
    let cls_name = lua_tostring(L!, -1)
    lua_pop(L!, 1)

    lua_pushstring(L, "__class")
    lua_rawget(L, 1)
    var ud = lua_touserdata(L, -1)!
    let cls: AnyClass = casting(&ud)
    print("cast back class: \(cls)")
    lua_pop(L!, 1)

    let key = lua_tostring(L!, -2)
    let sel = NSSelectorFromString(key.replacingOccurrences(of: "_", with: ":"))
    print("key: \(key) -> sel: \(sel)")

    // this is a one time call, we may take that burden
    var proto_methods = protocol_methods(protocols_of(cls))
    let cls_methods = class_methods(cls)
    // supers may implement the protol methods or in a category
    let common = cls_methods.intersection(proto_methods)

    if common.contains(sel) {
        print("\(common.count) common methods in class and protocols \(common) ")
        // ... to override?
        add_call(cls, sel)
        
    }

    return 0
}

let s_retain: @convention(c) (L_STATE?) -> Int32 = { L in
    lua_pushstring(L, "__swift_obj")
    lua_rawget(L, -2) // o, ptr
    let ptr = lua_touserdata(L, -1)!
    let obj: AnyObject = dereference(ptr)
    print("obj ref before retain: \(CFGetRetainCount(obj))")
    let _ = Unmanaged.passRetained(obj)
    print("obj ref after retain: \(CFGetRetainCount(obj))")
    
    lua_pop(L!, 1) // o
    
    return 0
}

private let regs: [luaL_Reg] = [
    reg("print_stack", s_print_stack),
    reg("c_hello", s_hello),
    reg("c_add_protocol_method", s_add_protocol_method),
    reg("c_retain", s_retain),
    null
]

public func luaopen_swifty(_ L: L_STATE) {
    luaL_newlib(L, regs)
    lua_setglobal(L, "swifty_G")
}
