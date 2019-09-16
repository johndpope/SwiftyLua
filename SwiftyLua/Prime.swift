//
//  Prime.swift
//  SwiftyLua
//
//  Created by hanzhao on 2018/1/21.
//  Copyright © 2018年 hanzhao. All rights reserved.
//

import Foundation

public protocol Ls { // Lua Stackable
    func push(_ L: L_STATE)
    static func load(_ L: L_STATE, _ idx: Int) -> Self
}

extension Int: Ls {
    public func push(_ L: L_STATE) {
        lua_pushinteger(L, lua_Integer(self))
    }

    public static func load(_ L: L_STATE, _ idx: Int) -> Int {
        return Int(lua_tointeger(L, idx))
    }
}

extension Int16: Ls {
    public func push(_ L: L_STATE) {
        lua_pushinteger(L, lua_Integer(self))
    }
    
    public static func load(_ L: L_STATE, _ idx: Int) -> Int16 {
        return Int16(lua_tointeger(L, idx))
    }
}

extension Int32: Ls {
    public func push(_ L: L_STATE) {
        lua_pushinteger(L, lua_Integer(self))
    }

    public static func load(_ L: L_STATE, _ idx: Int) -> Int32 {
        return Int32(lua_tointeger(L, idx))
    }
}

extension UInt: Ls {
    public func push(_ L: L_STATE) {
        lua_pushinteger(L, lua_Integer(self))
    }

    public static func load(_ L: L_STATE, _ idx: Int) -> UInt {
        return UInt(lua_tointeger(L, idx))
    }
}

extension Int64: Ls {
    public func push(_ L: L_STATE) {
        lua_pushinteger(L, lua_Integer(self))
    }

    public static func load(_ L: L_STATE, _ idx: Int) -> Int64 {
        return Int64(lua_tointeger(L, idx))
    }
}

extension UInt64: Ls {
    public func push(_ L: L_STATE) {
        lua_pushinteger(L, lua_Integer(self))
    }

    public static func load(_ L: L_STATE, _ idx: Int) -> UInt64 {
        return UInt64(lua_tointeger(L, idx))
    }
}

extension Double: Ls {
    public func push(_ L: L_STATE) {
        lua_pushnumber(L, lua_Number(self))
    }

    public static func load(_ L: L_STATE, _ idx: Int) -> Double {
        return lua_tonumber(L, idx)
    }
}

extension Float: Ls {
    public func push(_ L: L_STATE) {
        lua_pushnumber(L, lua_Number(self))
    }

    public static func load(_ L: L_STATE, _ idx: Int) -> Float {
        return Float(lua_tonumber(L, idx))
    }
}

extension CGFloat: Ls {
    public func push(_ L: L_STATE) {
        lua_pushnumber(L, lua_Number(self))
    }

    public static func load(_ L: L_STATE, _ idx: Int) -> CGFloat {
        return CGFloat(lua_tonumber(L, idx))
    }
}

extension String: Ls {
    public func push(_ L: L_STATE) {
        lua_pushstring(L, self)
    }

    public static func load(_ L: L_STATE, _ idx: Int) -> String {
        return lua_tostring(L, idx)
    }
}

extension Bool: Ls {
    public func push(_ L: L_STATE) {
        lua_pushboolean(L, self ? 1 : 0)
    }

    public static func load(_ L: L_STATE, _ idx: Int) -> Bool {
        return lua_toboolean(L, Int32(idx)) == 1
    }
}
