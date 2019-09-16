//
//  TypeReg.swift
//  SwiftyLua
//
//  Created by Zhao Han on 8/22/18.
//  Copyright © 2018 hanzhao. All rights reserved.
//

import Foundation

public enum TypeNote: String {
    case Enum = "enum"
    case `Protocol` = "protocol" // error: since it would conflict with the 'foo.Protocol' expression
    case Other = "other"
}

typealias BlockMap = [String : (L_STATE) -> Any]

open class TypeReg<T> {
    var L: L_STATE
    let t_name = String(describing: T.self)
    // public let trait: FuncTrait
    var meta_map: MetaMap
    var block_map = Ref(BlockMap())
    var type_note = TypeNote.Other
    
    lazy var arg_loader = {
        return ArgLoader(self.meta_map, self.block_map)
    }()
    
    public init<S>(_ L: L_STATE, _ meta_map: MetaMap, _ super_t: S.Type) where T: AnyObject {
        self.L = L
        print("TypeReg for \(T.self)")
        // self.trait = FuncTrait(L, meta_map, block_map)
        self.meta_map = meta_map
        
        create_meta(L, self.t_name, T.self, super_t)
        
        // for T? chasing
        meta_map.regPusher(T.self)
        // for array arg
        meta_map.regLoader([T].self)
        
        meta_map.regCaster(T.self, S.self)
    }
    
    public init(_ L: L_STATE, _ meta_map: MetaMap) {
        self.L = L
        print("TypeReg for \(T.self)")
        // self.trait = FuncTrait(L, meta_map, block_map)
        self.meta_map = meta_map
        
        create_meta(L, self.t_name, T.self)
        
        meta_map.regPusher(T.self)
        meta_map.regLoader([T].self)
        
        if is_objc(T.self) {
            print("\(T.self) is objc class")
        }
    }
    
    public init(_ L: L_STATE, _ meta_map: MetaMap, _ note: TypeNote) {
        self.L = L
        print("TypeReg for \(T.self)")
        // self.trait = FuncTrait(L, meta_map, block_map)
        self.meta_map = meta_map
        
        create_meta(L, self.t_name, T.self, nil, note)
        self.type_note = note
        
        if note == .Enum {
            // add a eq to compare userdata
            let eq = as_cfunc { L in // {}, userdata
                lua_getfield(L, -2, "__swift_obj") // {}, userdata, swift_obj
                
                let is_eq = lua_compare(L, -1, -2, LUA_OPEQ)
                lua_pop(L, 2)
                lua_pushboolean(L, is_eq == 1 ? 1 : 0)
                
                return 1
            }
            
            lua_pushstring(L, "eq")
            lua_pushcfunction(L, eq)
            lua_rawset(L, -3)
        }
    }
    
    private func isPrivate(_ name: String) -> Bool {
        let first = name.first!
        switch first {
        case "_", ".":
            return true
        default:
            return name.contains("_")
        }
    }
    
    public func end() {
        lua_settop(L, 0)
    }
    
    deinit {
        self.end()
    }
    
    // R should be T or T?, in swift ctor may also fail and return a T?
    @discardableResult
    public func ctor<R>(_ name: String, _ do_call: @escaping (L_STATE, ArgLoader) -> R) -> Self {
        let type_name = self.t_name
        
        let note = self.type_note
        print("ctor note: \(note)")
        let arg_loader = ArgLoader(meta_map, block_map)
        // { _swift_obj = userdata, __metatable -> {new, init, deinit, others} }
        let new_wrapper = as_cfunc { L in // meta, arg...
            print_stack(L, "enter ctor")
            lua_getfield(L, 1, "__name") // meta, __name
            let lua_type_name = lua_tostring(L, -1)
            if lua_type_name != type_name {
                print("expecting \(type_name), get \(lua_type_name)")
                assert(false)
            }
            // pop off name
            lua_pop(L, 1) // meta, arg...
            lua_remove(L, 1) // arg... -- meta has no use in `init`
            
            // new swift obj, arg_loader will pop off args
            var obj = do_call(L, arg_loader)
            print("ctor returned: \(obj) \(T.self) \(R.self) top \(lua_gettop(L))")
            
            if R.self != T.self {
                assert(Mirror(reflecting: obj).displayStyle == Mirror.DisplayStyle.optional)
                let casted_opt: T? = casting(&obj)
                if let casted = casted_opt {
                    print("casted to optional: \(String(describing: casted))")
                    var force = casted
                    
                    TypeReg.do_ctor(L, &force, type_name, note)
                } else {
                    print("casting failed")
                    lua_pushnil(L)
                }
            } else {
                print("ctor \(T.self), type note: \(note), type name: \(type_name)")
                TypeReg.do_ctor(L, &obj, type_name, note)
                
                print_stack(L, .bridge, "leave ctor")
            }
            return 1
        }
        
        lua_pushcclosure(L, new_wrapper, 0)
        lua_setfield(L, -2, name)
        
        return self
    }
    
    static private func do_ctor<T>(_ L: L_STATE, _ obj: inout T, _ type_name: String, _ note: TypeNote) {
        if T.self is AnyClass {
            create_luaobj(L, &obj)
        } else {
            create_lua_struct_for_obj(L, &obj, type_name, sizeof(T.self))
            if note == .Enum {
                lua_getfield(L, -1, "__swift_obj") // obj, userdata
                lua_getglobal(L, type_name) // obj, userdata, meta
                lua_setmetatable(L, -2) // obj, userdata
                lua_pop(L, 1) // obj
            }
        }
    }
    
    @discardableResult
    public func `enum`<A>(_ val: A, _ name: String) -> Self {
        let len = MemoryLayout<A>.size
        assert(len > 0)
        let ud = lua_newuserdata(L, len) // meta, ud
        
        // set enum's meta
        lua_pushvalue(L, -2) // meta, ud, meta
        lua_setmetatable(L, -2) // meta, ud
        
        var v = val
        // let casted: UnsafeMutableRawPointer = casting(&v)
        let _ = withUnsafeBytes(of: &v) { ptr in
            memcpy(ud, ptr.baseAddress, len)
        }
        
        lua_setfield(L, -2, name) // meta
        
        return self
    }
    
    // static method, no obj
    @discardableResult
    public func s_method<R>(_ name: String, _ call: @escaping (L_STATE, ArgLoader) -> R) -> Self {
        let arg_loader = ArgLoader(meta_map, block_map)
        let method_wrapper = as_cfunc { L in
            print_stack(L, .bridge, "call static: \(name)")
            var ret = call(L, arg_loader)
            
            return Int32(push_ret(L, &ret, self.meta_map))
        }
        
        lua_pushcclosure(L, method_wrapper, 0)
        lua_setfield(L, -2, name)
        
        return self
    }
    
    // inout T will be a mutable method for structure, means the structure itself is changed
    /*public func method<A, R>(_ method: @escaping (inout T) -> (A) -> (R), _ name: String, _ call: @escaping (L_STATE, T, MetaMap) -> R) {
     let method_wrapper = buildLuaFunc(name) { (L: L_STATE, obj: inout T) in
     return (call(L, obj, self.meta_map), true)
     }
     
     lua_pushcclosure(L, method_wrapper, 0)
     lua_setfield(L, -2, name)
     }*/
    
    @discardableResult
    public func method<R>(_ name: String, _ call: @escaping (L_STATE, T, ArgLoader) -> R) -> Self {
        
        let arg_loader = ArgLoader(meta_map, block_map)
        let map = self.meta_map
        let method_wrapper = buildLuaFunc(name) { (L: L_STATE, obj: inout T) in
            var ret = call(L, obj, arg_loader)
            return (push_ret(L, &ret, map), false)
        }
        
        lua_pushcclosure(L, method_wrapper, 0)
        lua_setfield(L, -2, name)
        
        return self
    }
    
    @discardableResult
    public func property<R>(_ name: String, _ call: @escaping (T) -> R) -> Self {
        let method_wrapper = buildLuaFunc(name) { (L: L_STATE, obj: inout T) in
            var ret = call(obj)
            return (push_ret(L, &ret, self.meta_map), false)
        }
        lua_pushcclosure(L, method_wrapper, 0)
        lua_setfield(L, -2, name)
        
        return self
    }
    
    @discardableResult
    public func property<R>(_ name: String, _ call: FuncTrait.MulProp<T, R>) -> Self {
        // getter
        let getter = buildLuaFunc("getter: " + name) { (L: L_STATE, obj: inout T) in
            var ret = call.getter(obj)
            return (push_ret(L, &ret, self.meta_map), false)
        }
        lua_pushcclosure(L, getter, 0)
        lua_setfield(L, -2, name)
        
        // setter
        let arg_loader = ArgLoader(meta_map, block_map)
        let new_index = buildLuaFunc("setter: " + name) { (L: L_STATE, obj: inout T) in
            // tbl, key, value
            let key = lua_tostring(L, 2)
            if key == name {
                let v: R = arg_loader.load(L)
                call.setter(obj, v)
            } else {
                assert(false)
            }
            
            return (0, false)
        }
        lua_pushcclosure(L, new_index, 0)
        lua_setfield(L, -2, "__newindex")
        
        return self
    }
    
    private func pusher_for_args() -> (L_STATE) -> Int {
        return { L in
            return 0
        }
    }
    
    private func pusher_for_args<A1>(_ a1: A1) -> (L_STATE) -> Int {
        return { L in
            var arg1 = a1
            push_ret(L, &arg1, self.meta_map)
            
            return 1
        }
    }
    
    private func pusher_for_args<A1, A2>(_ a1: A1, _ a2: A2) -> (L_STATE) -> Int {
        return { L in
            return self.pusher_for_args(a1)(L) + self.pusher_for_args(a2)(L)
        }
    }
    
    private func pusher_for_args<A1, A2, A3>(_ a1: A1, _ a2: A2, _ a3: A3) -> (L_STATE) -> Int {
        return { L in
            return self.pusher_for_args(a1, a2)(L) + self.pusher_for_args(a3)(L)
        }
    }
    
    private func pusher_for_args<A1, A2, A3, A4>(_ a1: A1, _ a2: A2, _ a3: A3, _ a4: A4) -> (L_STATE) -> Int {
        return { L in
            return self.pusher_for_args(a1, a2, a3)(L) + self.pusher_for_args(a4)(L)
        }
    }
    
    private func pusher_for_args<A1, A2, A3, A4, A5>(_ a1: A1, _ a2: A2, _ a3: A3, _ a4: A4, _ a5: A5) -> (L_STATE) -> Int {
        return { L in
            return self.pusher_for_args(a1, a2, a3, a4)(L) + self.pusher_for_args(a5)(L)
        }
    }
    
    @discardableResult
    public func block<A1, A2, A3, A4, A5, R>(_ type: ((A1, A2, A3, A4, A5) -> R).Type) -> Self {
        
        let key = "\(type)"
        if (block_map.val[key] != nil) {
            t_print("\(type) already registered on \(self)")
        } else {
            block_map.val[key] = { (L: L_STATE) -> Any in
                let call_ctx = BlockCallContext(L, key)
                
                return { [unowned self]  (a1: A1, a2: A2, a3: A3, a4: A4, a5: A5) -> R in
                    let callee_id = Thread.current.id
                    t_print("calling into block (5 arg \(type)), caller thread: \(call_ctx.thread), callee thread: \(callee_id)")
                    
                    return call_ctx.call_block(self.pusher_for_args(a1, a2, a3, a4, a5), self.arg_loader)
                }
            }
        }
        
        return self
    }
    
    @discardableResult
    public func block<A1, A2, A3, A4, R>(_ type: ((A1, A2, A3, A4) -> R).Type) -> Self {
        
        let key = "\(type)"
        if (block_map.val[key] != nil) {
            t_print("\(type) already registered on \(self)")
        } else {
            block_map.val[key] = { (L: L_STATE) -> Any in
                let call_ctx = BlockCallContext(L, key)
                
                return { [unowned self] (a1: A1, a2: A2, a3: A3, a4: A4) -> R in
                    let callee_id = Thread.current.id
                    t_print("calling into block (4 arg \(type)), caller thread: \(call_ctx.thread), callee thread: \(callee_id)")
                    
                    return call_ctx.call_block(self.pusher_for_args(a1, a2, a3, a4), self.arg_loader)
                }
            }
        }
        
        return self
    }
    
    @discardableResult
    public func block<A1, A2, A3, R>(_ type: ((A1, A2, A3) -> R).Type) -> Self {
        
        let key = "\(type)"
        if (block_map.val[key] != nil) {
            t_print("\(type) already registered on \(self)")
        } else {
            block_map.val[key] = { (L: L_STATE) -> Any in
                let call_ctx = BlockCallContext(L, key)
                
                return { [unowned self] (a1: A1, a2: A2, a3: A3) -> R in
                    let callee_id = Thread.current.id
                    t_print("calling into block (3 arg \(type)), caller thread: \(call_ctx.thread), callee thread: \(callee_id)")
                    
                    return call_ctx.call_block(self.pusher_for_args(a1, a2, a3), self.arg_loader)
                }
            }
        }
        
        return self
    }
    
    @discardableResult
    public func block<A1, A2, R>(_ type: ((A1, A2) -> R).Type) -> Self {
        
        let key = "\(type)"
        if (block_map.val[key] != nil) {
            t_print("\(type) already registered on \(self)")
        } else {
            block_map.val[key] = {(L: L_STATE) -> Any in
                let call_ctx = BlockCallContext(L, key)
                
                return { [unowned self] (a1: A1, a2: A2) -> R in
                    let callee_id = Thread.current.id
                    t_print("calling into block (2 arg \(type)), caller thread: \(call_ctx.thread), callee thread: \(callee_id)")
                    
                    return call_ctx.call_block(self.pusher_for_args(a1, a2), self.arg_loader)
                }
            }
        }
        
        return self
    }
    
    @discardableResult
    public func block<A1, R>(_ type: ((A1) -> R).Type) -> Self {
        let key = "\(type)"
        if (block_map.val[key] != nil) {
            t_print("\(type) already registered on \(self)")
        } else {
            block_map.val[key] = { (L: L_STATE) -> Any in
                let call_ctx = BlockCallContext(L, key)
                
                return { [unowned self]  (a1: A1) -> R in
                    let callee_id = Thread.current.id
                    t_print("calling into block (1 arg \(type)), caller thread: \(call_ctx.thread), callee thread: \(callee_id)")
                    
                    return call_ctx.call_block(self.pusher_for_args(a1), self.arg_loader)
                }
            }
        }
        
        return self
    }
    
    public typealias KFunc = (L_STATE, Int, lua_KContext) -> Int
    
    @discardableResult
    public func block<R>(_ type: (() -> R).Type) -> Self {
        
        let key = "\(type)"
        if (block_map.val[key] != nil) {
            t_print("\(type) already registered on \(self)")
        } else {
            block_map.val[key] = { (L: L_STATE) -> Any in
                let call_ctx = BlockCallContext(L, key)
                
                return { [unowned self] () -> R in
                    let callee_id = Thread.current.id
                    t_print("calling into block (0 arg \(type)), caller thread: \(call_ctx.thread), callee thread: \(callee_id)")
                    
                    return call_ctx.call_block(self.pusher_for_args(), self.arg_loader)
                }
            }
        }
        
        return self
    }
    
    // MARK: -
    
    private func buildLuaFunc<T>(_ name: String, _ f_block: @escaping (L_STATE, inout T) -> (Int, Bool)) -> lua_CFunction {
        print("build \(name) for \(T.self)")
        let is_class = T.self is AnyClass
        let is_enum = self.type_note == .Enum// MemoryLayout<T>.size == 1
        let is_proto = self.type_note == .Protocol
        
        return as_cfunc { L in
            // print_stack(L, .bridge, "calling: \(name) on \(T.self)")
            // print("calling: \(name) on \(T.self)")
            
            var obj: T
            var swift_ptr: UnsafeMutableRawPointer
            if is_enum {
                // when T is a value type, .pointee will do a value assign to obj, and the swift_ptr will
                // remain the same
                swift_ptr = lua_touserdata(L, 1)!
                obj = swift_ptr.bindMemory(to: T.self, capacity: 1).pointee
            } else {
                lua_getfield(L, 1, "__swift_type")
                let obj_type = lua_tostring(L, -1) // struct, class, enum?
                lua_pop(L, 1)
                
                lua_getfield(L, 1, "__passing_style")
                let style = lua_isnil(L, -1) ? "N/A" : lua_tostring(L, -1)
                lua_pop(L, 1)
                // print("__passing_style is: \(style)")
                
                // obj, args
                lua_pushstring(L, "__swift_obj")
                lua_gettable(L, 1)
                
                _ = lua_type(L, -1)
                // obj, args, _swift_obj
                assert(lua_isuserdata(L, -1) == 1)
                swift_ptr = lua_touserdata(L, -1)!
                
                if is_class || is_proto {
                    if style == ArgPassingStyle.byReference.rawValue {
                        obj = dereference(swift_ptr)
                    } else {
                        obj = swift_ptr.bindMemory(to: T.self, capacity: 1).pointee
                    }
                } else {
                    print("special case for \(T.self) \(MemoryLayout<T>.size), ptr \(swift_ptr)")
                    
                    if obj_type == "struct" {
                        if MemoryLayout<T>.size > 32 {
                            obj = swift_ptr.bindMemory(to: Any.self, capacity: 1).pointee as! T
                        } else {
                            obj = swift_ptr.bindMemory(to: T.self, capacity: 1).pointee
                        }
                        print("pointed: \(obj)")
                        
                    } else {
                        assert(false)
                        obj = swift_ptr as! T
                    }
                }
                
                // print("swift ptr \(swift_ptr) -> \(obj) \(T.self) bytes: \(hex(obj))")
                lua_pop(L, 1) // userdata
            }
            
            let (n, changed) = f_block(L, &obj)
            if changed {
                // .. so when a change is detected, we need to copy back the changed pointee to the
                //    swift_ptr pointed userdata in lua
                print("changed: \(hexString(bytes: bytes(of: obj)))")
                swift_ptr.initializeMemory(as: T.self, repeating: obj, count: 1)
            }
            
            return Int32(n)
        }
    }
}

