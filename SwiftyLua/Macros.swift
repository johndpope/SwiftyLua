//
//  Macros.swift
//  SwiftyLua
//
//  Created by hanzhao on 2017/2/12.
//  Copyright © 2017年 hanzhao. All rights reserved.
//

import Foundation
import LuaSource

// MARK: macros

public typealias L_STATE = UnsafeMutablePointer<lua_State>

let LUA_REGISTRYINDEX = SDegutisLuaRegistryIndex

func lua_pushcfunction(_ L: L_STATE, _ f: lua_CFunction!) {
    lua_pushcclosure(L, f, 0)
}

func lua_register(_ L: L_STATE, _ n: String, _ f: @escaping lua_CFunction) {
    lua_pushcfunction(L, f)
    lua_setglobal(L, n)
}

func luaL_newlib(_ L: L_STATE, _ funcs: [luaL_Reg]) {
    lua_createtable(L, 0, Int32(funcs.count) - 1)
    luaL_setfuncs(L, funcs, 0)
}

func luaL_getmetatable(_ L: L_STATE, _ n: String) -> Int {
    return Int(lua_getfield(L, LUA_REGISTRYINDEX, n))
}

func lua_pcall(_ L: L_STATE, _ nargs: Int, _ nresults: Int, _ errfunc: Int) -> Int {
    return Int(lua_pcallk(L, Int32(nargs), Int32(nresults), Int32(errfunc), 0, nil))
}

func lua_tostring(_ L: L_STATE, _ idx: Int) -> String {
    let v = lua_tolstring(L, Int32(idx), nil)
    return String(cString: v!)
}

func lua_tonumber(_ L: L_STATE, _ idx: Int) -> lua_Number {
    return lua_tonumberx(L, Int32(idx), nil)
}

func lua_tointeger(_ L: L_STATE, _ idx: Int) -> lua_Integer {
    return lua_tointegerx(L, Int32(idx), nil)
}

func lua_isnil(_ L: L_STATE, _ idx: Int) -> Bool {
    return lua_type(L, (idx)) == LUA_TNIL
}

func lua_istable(_ L: L_STATE, _ idx: Int) -> Bool {
    return lua_type(L, (idx)) == LUA_TTABLE
}

func lua_isfunction(_ L: L_STATE, _ idx: Int) -> Bool {
    return lua_type(L, idx) == LUA_TFUNCTION
}

func lua_isstring(_ L: L_STATE, _ idx: Int) -> Bool {
    return lua_type(L, idx) == LUA_TSTRING
}

func lua_type(_ L: L_STATE, _ idx: Int) -> Int32 {
    return lua_type(L, Int32(idx))
}

func lua_objlen(_ L: L_STATE, _ idx: Int) -> Int {
    return lua_rawlen(L, Int32(idx))
}

func lua_rawgetfield(_ L: L_STATE, _ idx: Int, _ name: String) {
    lua_pushstring(L, name)
    lua_rawget(L, Int32(idx))
}

// #define lua_insert(L,idx)	lua_rotate(L, (idx), 1)

// #define lua_remove(L,idx)	(lua_rotate(L, (idx), -1), lua_pop(L, 1))
func lua_remove(_ L: L_STATE, _ idx: Int) {
    lua_rotate(L, Int32(idx), -1)
    lua_pop(L, 1)
}

// #define lua_replace(L,idx)	(lua_copy(L, -1, (idx)), lua_pop(L, 1))

func luaL_loadfile(_ L: L_STATE, _ name: String) {
    let rslt = luaL_loadfilex(L, name, nil)
    if rslt != LUA_OK {
        print("load lua file error: \(rslt), \(lua_tostring(L, -1))")

        assert(false)
    }
}

func luaL_dofile(_ L: L_STATE, _ name: String, _ searchPath: String? = nil) {
    luaL_loadfile(L, name)

    var arg_n = 0
    if let path = searchPath {
        lua_pushstring(L, path)
        arg_n = 1
    }

    let error_fp = as_cfunc { L in
        return error_function(L)
    }

    lua_pushcclosure(L, error_fp, 0)

    arg_n += 1

    if lua_pcall(L, arg_n, Int(LUA_MULTRET), -1) != Int(LUA_OK) {
        print("error load file: \(lua_tostring(L, -1))")
        assert(false)
    }

}

@discardableResult
func luaL_dostring(_ L: L_STATE, _ body: String) -> Bool {
    return luaL_loadstring(L, body) != LUA_OK || lua_pcall(L, 0, Int(LUA_MULTRET), 0) != LUA_OK
}

func lua_pop(_ L: L_STATE, _ n: Int) {
    lua_settop(L, Int32(-n - 1))
}

func lua_newtable(_ L: L_STATE) {
    lua_createtable(L, 0, 0)
}

func lua_remove(_ L: L_STATE, _ range: CountableClosedRange<Int>) {
    range.forEach { i in
        lua_remove(L, range.lowerBound)
    }
}

func lua_insert(_ L: L_STATE, _ idx: Int) {
    lua_rotate(L, Int32(idx), 1)
}

func lua_lock(_ L: L_STATE) {
    wax_luaLock(L)
}

func lua_unlock(_ L: L_STATE) {
    wax_luaUnlock(L)
}

