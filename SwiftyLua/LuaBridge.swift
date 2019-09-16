//
//  Bridge.swift
//  Infinity
//
//  Created by hanzhao on 2017/1/30.
//  Copyright © 2017年 hanzhao. All rights reserved.
//

import Foundation
import LuaSource
import UIKit
import ObjectiveC.runtime
import ObjectiveC.message

private let print = Logger.genPrint(level: .bridge)
private let t_print = Logger.genTPrint(print)

public protocol EnumRawable {
    associatedtype T
    var rawValue: T {get}
}

public func wrapper<R>(_ mtd: @escaping () -> (R)) -> () -> (R){
    return {
        return mtd()
    }
}

public func wrapper<A, R>(_ mtd: @escaping (A) -> (R)) -> (Any) -> (R){
    return { (args: Any) in
        let flat_args: A = args_to(args)
        return mtd(flat_args)
    }
}

public func wrapper<O, A, R>(_ mtd: @escaping (O) -> (A) -> (R)) {
    print("void wrapper")
}

extension Thread {
    var bridge: LuaBridge? {
        get {return self.threadDictionary["__bridge"] as? LuaBridge}
    }
    
    @objc public var L: UnsafeMutablePointer<lua_State>? {
        get {return self.bridge?.L}
    }

    func regBridge(_ bridge: LuaBridge) {
        assert(self.bridge == nil)
        self.threadDictionary["__bridge"] = bridge
        // self.threadDictionary["__bridge_L"] = bridge.L

        // reg_L(bridge.L, self)
    }
}

open class LuaBridge {
    open var L: UnsafeMutablePointer<lua_State>
    open var meta_map: MetaMap
    var thread: Thread
    let locker = NSRecursiveLock()
    
    private var regs = [Any]()

    public init(start name: String, post_setup: @escaping (_ L: L_STATE, _ bridge: LuaBridge, _ trait: FuncTrait) -> ()) {

        L = luaL_newstate()!
        meta_map = MetaMap(L)

        luaL_openlibs(L)
        thread = Thread.current

        setupSwiftRegistry(L)
        bridgeReg(L, self.meta_map)
        post_setup(L, self, FuncTrait())

        luaopen_swifty(L)

        let arch = sizeof(Int.self) == sizeof(Int64.self) ? 64 : 32
        let scriptFolder = Bundle.main.bundlePath + "/scripts-\(arch)/"
        let init_script = scriptFolder + "loader.lua"
        luaL_dofile(L, init_script, scriptFolder)
        
        eval("require '\(name)'")

        // reg on thread
        Thread.current.regBridge(self)
    }

    // clone from
    public init (fromThread from: LuaBridge) {
        // thread will push on the from.L stack
        L = lua_newthread(from.L)
        
        meta_map = MetaMap(L)
        thread = Thread.current

        // reg the new L
        regThread(L, on: from.L)
    }

    public static func bridgeOnThread() -> LuaBridge {
        return Thread.current.threadDictionary["__bridge"] as! LuaBridge
    }
    
    public func gc() {
        print("-----> gc started on: ", L)
        lua_gc(L, LUA_GCCOLLECT, 0)
        print("<----- gc ends on: ", L)
    }

    @discardableResult
    public func const<R: Ls>(_ name: String, _ val: R) -> Self {
        lua_getglobal(L, "_G") // _G
        lua_pushstring(L, name) // _G, name
        val.push(self.L) // _G, name, val
        lua_rawset(L, -3) // _G

        lua_pop(L, 1)

        return self
    }
    
    public func locked<R>(_ cb: @escaping () -> R) -> R {
        locker.lock()
        let ret = cb()
        locker.unlock()
        return ret
    }

    private func registerPrime(_ meta_map: MetaMap) {
        meta_map.regPusher(Int.self)
        meta_map.regPusher(String.self)
        meta_map.regPusher(CGFloat.self)
        meta_map.regPusher(Float.self)
        meta_map.regPusher(Bool.self)
        meta_map.regPusher(Double.self)
        meta_map.regPusher(Int64.self)
        meta_map.regPusher(Int32.self)
        meta_map.regPusher([AnyHashable: Any].self)

        meta_map.regLoader(Int.self)
        meta_map.regLoader(Int?.self)
        meta_map.regLoader([Int].self)
        meta_map.regLoader(Int64.self)
        meta_map.regLoader(Int32.self)
        meta_map.regLoader(UInt.self)
        meta_map.regLoader([UInt].self)
        meta_map.regLoader(String.self)
        meta_map.regLoader(String?.self)
        meta_map.regLoader([String].self)
        meta_map.regLoader(CGFloat.self)
        meta_map.regLoader([CGFloat].self)
        meta_map.regLoader(Float.self)
        meta_map.regLoader([Float].self)
        meta_map.regLoader(Bool.self)
        meta_map.regLoader([Bool].self)
        meta_map.regLoader(Double.self)
        meta_map.regLoader([Double].self)

    }

    // new thread on top of L stack
    private func regThread(_ L: L_STATE, on fromL: L_STATE) {
        // print_stack(fromL, .bridge, " reg from L ")
        // move the thread over to thread stack
        // lua_xmove(fromL, L, 1)
        lua_pushthread(L)
        lua_pop(fromL, 1)
        
        // print_stack(L, .bridge, " dest L ")
        if (lua_type(L, 1) != LUA_TTHREAD) {
            print_stack(L, .bridge, "stack corrupt")
            assert(false)
        }

        lua_getglobal(L, "__thread_reg") // thread
        // print_stack(L, .bridge, "reg thread")
        if lua_isnil(L, -1) {// thread, nil
            lua_pop(L, 1)

            lua_newtable(L) // thread, reg
            lua_rotate(L, -2, 1) // reg, thread
            print_stack(L, .bridge, "rotate")
            lua_setfield(L, -2, key(L)) // reg
            lua_setglobal(L, "__thread_reg")
            print_stack(L, .bridge, "post")
        } else {
            assert(lua_istable(L, -1)) // thread, reg
            lua_rotate(L, -2, 1) // reg, thread
            lua_setfield(L, -2, key(L)) // reg

            lua_pop(L, 1)
        }
    }

    private func unregThread(_ L: L_STATE) {
        lua_getglobal(L, "__thread_reg") // reg
        assert(lua_istable(L, -1))

        lua_getfield(L, -1, key(L))
        assert(lua_type(L, -1) == LUA_TTHREAD)
        lua_pop(L, 1)

        lua_pushnil(L)
        assert(lua_gettop(L) == 2) // reg, nil

        print_stack(L, .bridge, "unreg thread for \(L)")
        lua_setfield(L, -2, key(L))
    }

    private func key(_ L: L_STATE) -> String {
        return "L thread key: [\(L)]"
    }

    deinit {
        print("close L \(L) on thread [\(Thread.current.id)]")
        locker.lock()
            unregThread(L)
        locker.unlock()
    }

    @discardableResult
    public func reg<T>(_ t: T.Type) -> TypeReg<T> {
        return TypeReg<T>(L, meta_map)
    }
    
    @discardableResult
    public func reg<T>(_ t: T.Type, _ note: TypeNote) -> TypeReg<T> {
        return TypeReg<T>(L, meta_map, note)
    }

    @discardableResult
    public func reg<T, S>(_ t: T.Type, _ s: S.Type) -> TypeReg<T> where T: AnyObject {
        return TypeReg<T>(L, meta_map, s)
    }

    public func eval(_ str: String) {
        if luaL_loadstring(L, str) == LUA_OK {
            _ = lua_pcall(L, 0, Int(LUA_MULTRET), 0)
        } else {
            assert(false)
        }
    }

    internal func setupSwiftRegistry(_ L: L_STATE) {
        createRegTable(L, "__swift_reg")
        createRegTable(L, "__block_reg", mode: "") // blocks
        createRegTable(L, "__cross_reg", mode: "") // __ctor-ed obj, hold strong and release in dealloc
    }

    internal func createRegTable(_ L: L_STATE, _ name: String, mode: String = "v") {
        lua_newtable(L) // {}
        lua_pushvalue(L, -1) // {}, {}
        lua_setglobal(L, name) // {}

        if mode.count > 0 {
            // meta for weak
            lua_newtable(L) // {}, {}
            lua_pushstring(L, mode) // {}, {}, "v"
            lua_setfield(L, -2, "__mode") // {}, {__mode = 'v'}
            
            // __newindex to track inserting
            lua_pushcfunction(L, as_cfunc { L in // tbl, key, val
                switch lua_type(L, 2) {
                case LUA_TUSERDATA, LUA_TLIGHTUSERDATA:
                    print("set reg [\(name)]: \(String(describing: lua_touserdata(L, 2)))")
                case LUA_TSTRING:
                    print("set reg [\(name)]: \(lua_tostring(L, 2))")
                default:
                    assert(false)
                }
                lua_rawset(L, 1)
                return 0
            })

            lua_setfield(L, -2, "__newindex")
            
            lua_setmetatable(L, -2) // {}
        }

        lua_pop(L, 1)
    }

    internal func bridgeReg(_ L: L_STATE, _ meta_map: MetaMap) {
        LuaClass.L = L
        LuaClass.meta_map = meta_map

        let trait = FuncTrait()

        self.reg(LuaClass.self)
            .ctor("init", trait.static(LuaClass.init))

        self.reg(LogLevel.self, .Enum)
            .enum(LogLevel.create, "create")
            .enum(LogLevel.class, "class")
            .enum(LogLevel.args, "args")
            .enum(LogLevel.expose, "expose")
            .enum(LogLevel.return, "return")
            .enum(LogLevel.trait, "trait")
            .enum(LogLevel.lab, "lab")

        registerPrime(meta_map)
    }

    // MARK: playground to try new ideas

}
