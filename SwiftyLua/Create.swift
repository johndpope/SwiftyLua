//
//  Create.swift
//  SwiftyLua
//
//  Created by hanzhao on 2017/2/25.
//  Copyright © 2017年 hanzhao. All rights reserved.
//

import Foundation
import LuaSource

private let print = Logger.genPrint(level: .create)

public enum ArgPassingStyle: String {
    case byReference = "by_reference"
}

extension String {
    public func className() -> String {
        if let last_dot = self.range(of: ".", options: .backwards)?.lowerBound {
            // return self.substring(from: self.index(after: last_dot))
            return String(self[self.index(after: last_dot)...])
        } else {
            return self
        }
    }
}

func is_objc<T>(_ t: T.Type) -> Bool {
    if is_ref(t) {
        if let cls = T.self as? AnyClass {
            var cur_cls: AnyClass = cls
            var spr_cls: AnyClass = cur_cls
            while true {
                print("cur \(cur_cls)")
                if spr_cls == NSObject.self {
                    return true
                }

                if let spr = class_getSuperclass(cur_cls) {
                    spr_cls = spr
                    
                    print("super \(spr_cls), cur \(cur_cls)")
                    if spr_cls == cur_cls {
                        break
                    }

                    if spr_cls.description().contains("SwiftObject") {
                        break
                    }

                    cur_cls = spr_cls
                } else {
                    break
                }
            }
        }
    }
    return false
}

public func create_meta<T, S> (_ L: L_STATE, _ t_name: String, _ t: T.Type, _ s: S.Type) {
    let super_name = String(describing: s)
    create_meta(L, t_name, t, super_name)
}

public func create_meta<T>(_ L: L_STATE, _ t_name: String, _ t: T.Type, _ super_name: String? = nil, _ note: TypeNote? = nil) {
    assert(t_name.range(of: ".") == nil)
    let l_type = Int32(luaL_getmetatable(L, t_name))
    if l_type == LUA_TNIL {
        lua_pop(L, 1)

        luaL_newmetatable(L, t_name) // meta

        if is_objc(t) {
            lua_newtable(L) // meta, class_meta
            
            // put a class meta note
            lua_pushstring(L, "class: " + t_name)
            lua_setfield(L, -2, "class_meta")
            
            let class_indexing = objcClassMethodIndex(L, t)

            lua_pushcclosure(L, class_indexing, 0) // meta, class_meta, indexing
            lua_setfield(L, -2, "__index") // meta, class_meta
            
            // chain the sub-super meta (meta -> class_meta -> super_meta is not only in objc)
            if let t_super = super_name {
                lua_getglobal(L, t_super) // meta, class_meta, super_meta
                lua_setmetatable(L, -2) // meta, class_meta (now pointed to super)
            }

            lua_setmetatable(L, -2) // meta
        } else {
            // record size: in case return a subclass obj/struct etc
            lua_pushinteger(L, lua_Integer(sizeof(T.self))) // meta, size
            lua_setfield(L, -2, "__size") // meta
            
            if let t_super = super_name {
                lua_getglobal(L, t_super) // meta, super_meta
                lua_setmetatable(L, -2)
            }
        }

        if let note_info = note {
            lua_pushstring(L, note_info.rawValue)
            lua_setfield(L, -2, "__note")

            if note_info == .Enum {
                // compare a enum object to userdata
                // note:
                //   Behavior similar to the addition operation, except that Lua will try a metamethod
                //   only when the values being compared are either both tables or both full userdata and they are not primitively equal.
                let eq = as_cfunc { L in // enum obj, rhs raw
                    // lua_getfield(L, -2, "__swift_obj") // enum obj, rhs raw, lhs raw
                    assert(lua_isuserdata(L, -1) == 1)
                    if lua_rawlen(L, -1) != lua_rawlen(L, -2) {
                        lua_pushboolean(L, 0)
                    } else {
                        let lhs = lua_touserdata(L, -1)!
                        let rhs = lua_touserdata(L, -2)!
                        let len = lua_rawlen(L, -1) // lhs, rhs

                        let cmp = memcmp(lhs, rhs, Int(len))
                        lua_pushboolean(L, cmp == 0 ? 1 : 0)
                    }

                    return 1
                }

                lua_pushstring(L, "__eq")
                lua_pushcfunction(L, eq) // meta, "__eq", eq
                lua_rawset(L, -3)
            }
        }

        lua_pushvalue(L, -1)
        lua_setglobal(L, t_name) // _G[T] = meta

        if is_objc(t) {
            // property set
            print("checking properties for: \(t)")
            let new_indexing = objcInstanceSetProperty(t)
            lua_pushcclosure(L, new_indexing, 0) // meta, meta, newindex_func
            lua_setfield(L, -2, "__newindex")

            // instance method
            let instance_indexing = objcInstanceMethodIndex(t, t_name)
            lua_pushcclosure(L, instance_indexing, 0) // meta, index_func
        } else {
            lua_pushvalue(L, -1) // meta, meta
        }

        // meta.__index = meta for swift 
        // or indexing function for objc
        lua_setfield(L, -2, "__index") // meta

        // __gc
        let gc = gcMethod(L, t)
        lua_pushcclosure(L, gc, 0) // meta, gc
        lua_setfield(L, -2, "__gc")

    } else {
        assert(l_type == LUA_TTABLE)
        // non
    }
}

private func lookUpRegisteredClass(_ L: L_STATE, _ type: AnyClass) -> (String, String?) {
    let names = withSupers(type).map { cls -> String in
        let full_name = String(validatingUTF8: UnsafePointer<CChar>(class_getName(cls)))!

        if let last_dot = full_name.range(of: ".", options: String.CompareOptions.backwards, range: nil, locale: nil) {
            let start = full_name.index(after: last_dot.lowerBound)
            // return full_name.substring(from: start)
            return String(full_name[start...])
        } else {
            return full_name
        }
    }
    print("lookup reg class: \(type), names: \(names)")
    var chain = ""
    for name in names {
        chain += name
        lua_getglobal(L, name)
        if lua_istable(L, -1) {
            lua_pop(L, 1)
            return (names[0], chain == name ? nil : chain)
        }
        lua_pop(L, 1) // pop off nil

        chain += "->"
    }
    print("no registered class for \(type)")
    assert(false)
    return ("N/A", nil);
}

public class SwiftyLua : NSObject {
    public struct config {
        public static var log = true
    }

    @objc public static func printStack(_ L: L_STATE, message: String) {
        print_stack(L, .create, message);
    }

    @objc public static func typeOf(_ L: L_STATE, ptr: UnsafeMutableRawPointer) -> String? {
        // print_stack(L, "before type of \(ptr)")
        
        lua_getglobal(L, "__swift_reg")
        lua_pushlightuserdata(L, ptr) // reg, ptr
        lua_gettable(L, -2) // reg, obj
        
        if lua_isnil(L, -1) {
            lua_pop(L, 2) // reg, nil
            return nil
        }
        
        // lua_getfield(L, -1, "__objc_type")
        lua_pushstring(L, "__objc_type") // reg, obj, "__objc_type"
        lua_rawget(L, -2) // reg, obj, type?
        if lua_isnil(L, -1) {
            lua_pop(L, 3) // reg, obj, type
            return nil
        }
        
        let type = lua_tostring(L, -1)
        lua_pop(L, 3) // reg, obj, type
        return type
    }
    
    // passing NSObj from objc -> lua, should NOT change the reference count
    @objc public static func referenceNSObj(L: L_STATE, obj: NSObject, type: AnyClass) -> Void {
        let real_cls: AnyClass = object_getClass(obj)!
        //if (real_cls != type) {
        print("type checking when create NS obj: \(real_cls) \(type) ref: \(CFGetRetainCount(obj))")
        //}
        let (cur_name, chain) = lookUpRegisteredClass(L, type)
        print("lookup \(cur_name) \(chain ?? "NO CHAIN")")
        var obj_p = obj
        create_luaobj(L, &obj_p, cur_name, chain, type, passing: .byReference)
        // create_luaobj(L, &obj_p, cur_name, chain, type)
        print("post create ref: \(CFGetRetainCount(obj))")
    }

    @objc public static func createNSStruct(L: L_STATE, obj: UnsafeMutableRawPointer, type: String, size: Int) -> Void {
        create_lua_struct_for_ptr(L, obj, type, size)
    }

    @objc public static func findRegistered(L: L_STATE, ptr: UnsafeMutableRawPointer) -> Bool {
        // register ptr map
        lua_getglobal(L, "__swift_reg") // reg
        assert(lua_istable(L, -1))

        lua_pushlightuserdata(L, ptr)
        lua_gettable(L, -2)

        if lua_istable(L, -1) {// reg, obj
            lua_getfield(L, -1, "__swift_obj")
            if lua_isuserdata(L, -1) == 1 { // reg, obj, userdata
                lua_pop(L, 1) // reg, obj
                lua_remove(L, -2) // obj
                return true
            }
            lua_pop(L, 1)
        }

        // cleanup
        lua_pop(L, 2)

        return false
    }
}

public var g_struct_ptr: UnsafeMutableRawPointer!

@discardableResult
func create_lua_struct_for_obj<T>(_ L: L_STATE, _ obj: inout T, _ type: String, _ size: Int) -> UnsafeMutableRawPointer {

    // lua obj holder
    lua_newtable(L) // {}

    lua_getglobal(L, type) // {}, meta
    assert(lua_istable(L, -1))

    lua_setmetatable(L, -2) // { __metatable -> {}}

    // var boxed = Box(obj)
    // let len = sizeof(Box<T>.self)
    // struct is value type, no need for registry
    let ptr = lua_newuserdata(L, size)! // {}, ptr
    // memcpy(ptr, &obj, size)
    //memset(ptr, 0, len)
    let _ = ptr.initializeMemory(as: T.self, repeating: obj, count: 1)
    // let binded_ptr = ptr.initializeMemory(as: Box<T>.self, from: &boxed, count: 1) //(as: Box<T>.self, to: obj)
    lua_setfield(L, -2, "__swift_obj")
    print("lua struct created \(T.self) <- \(type): ptr \(ptr), orig obj \(obj), size \(size)")

    // let back = ptr.bindMemory(to: T.self, capacity: 1).pointee
    // print("bind back: \(back)")

    lua_pushstring(L, "struct")
    lua_setfield(L, -2, "__swift_type")

    // __struct = ...
    lua_pushstring(L, type)
    lua_setfield(L, -2, "__struct")

    // a cast func to handle the type mismatch
    /*let c_caster = as_cfunc { (L) -> Int32 in
        var back = ptr.bindMemory(to: T.self, capacity: 1).pointee
        lua_pushlightuserdata(L, &back)
        return 1
    }
    lua_pushcfunction(L, c_caster)
    lua_setfield(L, -2, "__cast")*/


    /*// reg to prevent userdata from gc
    lua_getglobal(L, "__swift_reg") // {}, reg
    let obj_address: UnsafeMutableRawPointer = casting(&obj)
    lua_pushlightuserdata(L, obj_address) // {}, reg, address
    lua_pushvalue(L, -3) // {}, reg, address, {}
    lua_settable(L, -3) // {}, reg
    lua_pop(L, 1) // {}*/

    return ptr
}

public func on_bg(wait: Bool, _ block: @escaping ()->()) {
    let bg_dispatcher = { (blk: @escaping ()->()) in
        DispatchQueue.global(qos: DispatchQoS.QoSClass.default).async {
            blk()
        }
    }
    on_dispatch(wait: wait, dispatcher: bg_dispatcher, block)
}

private func on_dispatch(wait: Bool = false, dispatcher: (@escaping ()->()) -> (), _ block: @escaping ()->()) {
    if wait {
        let cond = NSCondition()

        var done = false
        dispatcher {
            block()

            cond.lock()
            done = true
            cond.signal()
            cond.unlock()
        }

        cond.lock()
        while !done {
            cond.wait()
        }
        cond.unlock()
    } else {
        dispatcher(block)
    }
}

@discardableResult
func create_lua_struct_for_ptr(_ L: L_STATE, _ obj: UnsafeMutableRawPointer, _ type: String, _ size: Int) -> UnsafeMutableRawPointer {
    // lua obj holder
    lua_newtable(L) // {}

    lua_getglobal(L, type) // {}, meta
    assert(lua_istable(L, -1))

    lua_setmetatable(L, -2) // { __metatable -> {}}

    // struct is value type, no need for registry
    let ptr = lua_newuserdata(L, size)! // {}, ptr
    memcpy(ptr, obj, size)
    lua_setfield(L, -2, "__swift_obj")
    print("lua struct created: ptr \(ptr), obj \(obj), size \(size)")
    
    // __swift_type = struct
    lua_pushstring(L, "struct")
    lua_setfield(L, -2, "__swift_type")

    // __struct = ...
    lua_pushstring(L, type)
    lua_setfield(L, -2, "__struct")

    return ptr
}

@discardableResult
public func create_luaobj<T>(_ L: L_STATE, _ obj: inout T?, _ t_name: String? = nil, _ chain: String? = nil, passing style: ArgPassingStyle? = nil) -> UnsafeMutableRawPointer {
    var o = obj!
    return create_luaobj(L, &o, t_name, chain, passing: style)
}

@discardableResult
public func create_luaobj<T>(_ L: L_STATE, _ obj: inout T, _ t_name: String? = nil, _ chain: String? = nil, _ type: AnyClass? = nil, passing style: ArgPassingStyle? = nil) -> UnsafeMutableRawPointer {
    let obj_address = is_ref(T.self) ? address(of: &obj) : pointer(of: &obj)
    let type_name = t_name ?? String(describing: T.self)
    print("is_class: \(is_class(T.self)) is_ref: \(is_ref(T.self)) passing style: \(String(describing: style))")
    print("create luaobj: \(T.self) \(t_name ?? "N/A") address: \(obj_address) bytes: \(hex(obj, reverse: true))")

    // DEBUG:
    // let bind_back = obj_address.bindMemory(to: T.self, capacity: 1)
    // print("bind back ptr: \(bind_back), obj: \(bind_back.pointee)")
    
    if SwiftyLua.config.log {
        // t_print("casting \(abbr(obj)) to pointer \(obj_address) for \(T.self) \(type_name) \(String(describing: t_name)), top \(lua_gettop(L))")
    }

    let pre_top = lua_gettop(L)
    // print_stack(L)

    // lua obj holder
    lua_newtable(L) // {}

    lua_getglobal(L, type_name)
    if lua_isnil(L, -1) {
        // pop off nil
        lua_pop(L, 1)

        if let as_class = type ?? (T.self as? AnyClass) {
            let supers = withSupers(as_class)
            print("supers: \(supers)")
            for spr in supers {
                let name = "\(spr)"
                lua_getglobal(L, name)
                if lua_istable(L, -1) {
                    break
                }
                lua_pop(L, 1)
            }
        } else {
            // value types
            // ... non
        }
    } else {
        assert(lua_istable(L, -1))
    }

    lua_setmetatable(L, -2) // { __metatable -> {}}
    
    if let passing_style = style {
        lua_pushstring(L, "__passing_style")
        lua_pushstring(L, passing_style.rawValue)
        lua_rawset(L, -3) // { __metatable -> {}, __passing_style -> 'by_reference'}
    }

    // register ptr map
    lua_getglobal(L, "__swift_reg") // {}, reg

    lua_pushstring(L, "__swift_obj")

    //if let objp = obj as? NSObject {
        // print("pre reference count (\(obj)): \(CFGetRetainCount(objp))")
    //}
    if style == .byReference {
        lua_pushlightuserdata(L, obj_address) // // {}, reg, '__swift_obj', lightuserdata
        let _ = Unmanaged.passRetained(obj as AnyObject).autorelease()
    } else {
        /*let len = MemoryLayout<T>.size
        let ptr = lua_newuserdata(L, len)! // {}, reg, '__swift_obj', userdata
        // ctor & retain
        let binded_ptr = ptr.initializeMemory(as: T.self, repeating: obj, count: 1)
        print("\(ptr) binded to \(T.self) size \(MemoryLayout<T>.size) as \(binded_ptr)")*/
        
        let ptr = lua_newuserdata(L, MemoryLayout<Unmanaged<AnyObject>>.size)!
        let binded = ptr.bindMemory(to: Unmanaged<AnyObject>.self, capacity: 1)
        binded.pointee = Unmanaged.passRetained(obj as AnyObject) // .autorelease()
        if T.self != LuaClass.self {
            // let _ = binded.pointee.autorelease()
        }
    }
    //if let objp = obj as? NSObject {
        // print("after reference count (\(obj)): \(CFGetRetainCount(objp))")
    //}
    
    lua_rawset(L, -4) // {}, reg

    lua_pushlightuserdata(L, obj_address)
    lua_pushvalue(L, -3) // {}, reg, obj_address, {}
    lua_settable(L, -3) // {}, reg

    lua_pop(L, 1) // {}

    // type
    let ref = Mirror(reflecting: obj)
    if ref.displayStyle?.name == nil {
        print("no display style for \(obj)")
    }

    // objc type (class & struct) has no display name
    var type = "N/A"
    if T.self == Data.self {
        type = ref.displayStyle!.name // struct
    } else {
        type = obj is NSObject ? "objc_type" : (ref.displayStyle?.name ?? "N/A")
    }
    if type == "N/A" {
        print("creating \(type) \(obj) \(obj is NSObject))")
    }
    lua_pushstring(L, "__swift_type")
    lua_pushstring(L, type) // {}, __swift_type, type
    // lua_setfield(L, -2, "__swift_type") // {__swift_type = type}
    lua_rawset(L, -3)

    lua_pushstring(L, "__" + type)
    lua_pushstring(L, type_name)
    // lua_setfield(L, -2, "__" + type)
    lua_rawset(L, -3)

    if let inherit = chain {
        lua_pushstring(L, "__chain")
        lua_pushstring(L, inherit)
        print("chained up \(inherit)")
        // lua_setfield(L, -2, "__chain")
        lua_rawset(L, -3)
    }

    // print_stack(L, "before clear")

    let post_top = lua_gettop(L)
    assert(post_top == pre_top + 1)
    
    return obj_address
}

private func withClass<T>(class: AnyClass, access: (AnyClass?, UnsafeMutablePointer<UInt32>?) -> UnsafeMutablePointer<T>?, call: (_ t: T) -> Bool) {
    var n: UInt32 = 0
    if let props = access(`class`, &n) {

        for i in 0..<n {
            let prop_ptr = props.advanced(by: Int(i))
            let prop = prop_ptr.pointee

            if call(prop) {
                break
            }
        }
        free(props)
    } else {
        print("no properties for \(T.self)")
    }
}

// MARK: - helpers -

private func gcMethod<T>(_ xL: L_STATE, _ t: T.Type) -> lua_CFunction {
    /*return as_cfunc { L in
        return 0
    }*/
    return doGC(xL, t)
}

private func doGC<T>(_ xL: L_STATE, _ t: T.Type) -> lua_CFunction {
    return as_cfunc { L in
        print_stack(L, .create, "gc start in [\(Thread.current.id)] for \(t)")

        let l_type = lua_type(L, 1)
        if l_type == LUA_TNIL {
            return 0
        } else if l_type == LUA_TUSERDATA {
            // enum?
            lua_getmetatable(L, 1) // obj, meta
            print_stack(L, .create, "gc meta")
            lua_getfield(L, -1, "__note") // obj, meta, note
            assert(lua_type(L, -1) == LUA_TSTRING)
            let note = lua_tostring(L, -1)
            assert(TypeNote(rawValue: note) == .Enum)
            lua_pop(L, 2) // obj

            return 0
        }
        assert(l_type == LUA_TTABLE)

        lua_getfield(L, -1, "__swift_type") // {}, type
        let swift_type = lua_tostring(L, -1)
        lua_pop(L, 1) // {}
        if swift_type == /*Mirror.DisplayStyle.class.name*/ "objc_type" {
            lua_pushstring(L, "dtor")
            lua_rawget(L, 1)
            if lua_isfunction(L, -1) {
                lua_pushvalue(L, 1)
                if lua_pcall(L, 1, 0, 0) != LUA_OK {
                    print("failed to call dtor: \(lua_tostring(L, -1))")
                    assert(false)
                }
            }
            lua_pop(L, 1)
            
            lua_pushstring(L, "__swift_obj")
            lua_rawget(L, 1)
            
            // if lua_isuserdata(L, 2) == 1 {
            switch lua_type(L, 2) {
            case LUA_TLIGHTUSERDATA:
                let ptr = lua_touserdata(L, 2)!
                print("__gc ~: \(T.self) light userdata: \(ptr)")
                lua_pushstring(L, "__passing_style")
                lua_rawget(L, 1)
                
                let passing_style = lua_tostring(L, -1)
                assert(passing_style == ArgPassingStyle.byReference.rawValue)
                
            case LUA_TUSERDATA:
                let ptr = lua_touserdata(L, 2)!
                
                let len = lua_rawlen(L, 2)
                assert(len > 0)

                // userdata memory is managed by lua
                // ptr?.deallocate(bytes: len, alignedTo: 0)
                
                // check weak table first
                lua_getglobal(L, "__swift_reg")
                lua_pushlightuserdata(L, ptr) // reg, ptr
                lua_rawget(L, -2) // reg, obj?
                let top_obj = lua_type(L, -1)
                lua_pop(L, 2)
                
                assert(top_obj == LUA_TNIL)
                let binded = ptr.bindMemory(to: T.self, capacity: 1)
                print("__gc ~: \(T.self) userdata \(ptr) \(binded) \(binded.pointee)")
                // expecting a deinit call for class obj
                let reflect = Mirror(reflecting: binded.pointee)
                print("refelected: \(reflect)")
                if reflect.displayStyle == .class {
                    // force release
                    objc_removeAssociatedObjects(binded.pointee)

                    print("binded de-init \(binded)")
                    binded.deinitialize(count: 1) // multi dtor?
                    print("after binded de-init: \(binded)")
                }
                
            case LUA_TNIL:
                print("__swift_obj cleared already")
                
            default:
                print("expecting userdata, get \(lua_type(L, 2))")
                assert(false)
            }
        } else {
            // let td = "\(Thread.current)"
            print_stack(L, .create, "__gc ~: \(T.self): no deinit for type")

        }

        return 0
    }
}

private func objcInstanceMethodIndex<T>(_ t: T.Type, _ t_name: String) -> lua_CFunction {
    return as_cfunc { L in
        // t, key
        let method_name = lua_tostring(L, -1)
        // print("indexing \(method_name) for \(t_name): total stacks: \(lua_gettop(L))")
        // print_stack(L, .create)

        // check if it's a method set on lua side
        lua_rawget(L, -2)
        if lua_isfunction(L, -1) {// t, func
            lua_remove(L, -2) // func

            return 1
        } else if (lua_isnil(L, -1)) {
            // print_stack(L, .create, "indexing \(method_name) failed")
            lua_pop(L, 1)

            // restore stack
            lua_pushstring(L, method_name)
        } else {
            // print_stack(L, .create, "indexing \(method_name) got non-function type: \(lua_type(L, -1))")
            // remove t, leave only property on stack
            lua_remove(L, -2) // property
            
            return 1
        }

        // check meta table first
        lua_getmetatable(L, -2) // t, key, meta
        lua_pushstring(L, method_name) // t, key, meta, key
        lua_rawget(L, -2) // t, key, meta, method

        // print_stack(L)

        // prefer registered function first
        if lua_isfunction(L, -1) {
            // print("registered function found \(method_name)")
            // clean up underlying
            let n = Int(lua_gettop(L))
            assert(n > 3)
            lua_insert(L, n - 3) // method, t, key, meta
            lua_pop(L, 3) // method
            // lua_remove(L, 1...3)

            return 1
        } else {
            assert(lua_isnil(L, -1)) // t, key, meta, nil
            lua_pop(L, 1) // t, key, meta

            lua_pushstring(L, "__objc_type") // t, key, meta, '__objc_type'
            lua_rawget(L, -4) // t, key, meta, clsname
            let cls_name = lua_tostring(L, -1)
            lua_pop(L, 1) // t, key, meta
            let n = Int(lua_gettop(L))
            lua_insert(L, n - 2) // meta, t, key
            lua_pop(L, 2)
            // lua_remove(L, 1...2) // meta

            if cls_name != "\(t)" {
                print("subclass object passed in \(cls_name) -> \(t)")
            }

            let cls: AnyClass = T.self as! AnyClass

            print("matching selector \(method_name) for: \(T.self) \(t_name)")
            if let (mtd, matched_cls) = matchedSelector(withSupers(cls), method_name) {
                print("found: \(method_name) \(mtd) on \(matched_cls)")
                let lua_func = as_cfunc { L in
                    print("----> calling method: \(method_name)")
                    return call_objc(L, mtd, cls)
                }

                if matched_cls != T.self {
                    // matched on super
                    lua_pop(L, 1) // ^ instead of meta, using super_meta
                    let super_name = matched_cls.description().className()
                    lua_getglobal(L, super_name) // super_meta

                    if !lua_istable(L, -1) {
                        print("\(super_name) is not registered to lua yet!")
                        assert(false)
                    }
                }

                // set to meta table, so next time there'll be a match
                lua_pushcclosure(L, lua_func, 0) // meta, func
                lua_setfield(L, -2, method_name) // meta
                lua_pop(L, 1) // ^

                // ret
                lua_pushcclosure(L, lua_func, 0)
                
                return 1
            } else {
                print("not found \(method_name) for \(T.self) in \(methodNames(T.self as! AnyClass).count)) methods")
                
                lua_pop(L, 1) // pop off meta
                return 0
            }
        }
    }
}

// __newindex
private func objcInstanceSetProperty<T>(_ t: T.Type) -> lua_CFunction {
    let propers = Set(propertyNames(T.self as! AnyClass))
    // let reserved_prefix = "__"
    let ignores = Set(["__class", "__swift_obj", "__swift_type", "__objc_type", "__passing_style"])

    return as_cfunc { L in
        print_stack(L, .create, "set property on \(t)")
        // tbl, key, value
        let key = lua_tostring(L, -2)

        if ignores.contains(key) {
            lua_rawset(L, -3)
            return 0
        }

        print("setting \(key) on \(T.self), top \(lua_gettop(L)), propers \(propers)")
        if propers.contains(key) {
            // set objc property
            print("setting objc: \(T.self) -> \(key)")

            let cls: AnyClass = T.self as! AnyClass

            set_ivar(L, cls, key)
        } else {
            // normal set in lua
            lua_rawset(L, -3)
        }

        print("after set, top \(lua_gettop(L))")
        print_stack(L, .create)

        return 0
    }
}

private func objcClassMethodIndex<T>(_ L: L_STATE, _ t: T.Type) -> lua_CFunction {
    return as_cfunc { L in
        // t, key
        var method_name = lua_tostring(L, -1)
        lua_pop(L, 1) // t

        method_name = method_name.replacingOccurrences(of: "_", with: ":")

        let cls: AnyClass = T.self as! AnyClass
        let meta_classes = withSupers(cls).map {object_getClass($0)!}
        let meta_class: AnyClass = object_getClass(cls)!
        print("class \(cls), metas: \(meta_classes)")

        let push_func: (Method, AnyClass) -> () = { mtd, targeted_cls in
            let lua_func = as_cfunc { L in
                let type_encoding = String(cString: method_getTypeEncoding(mtd)!)
                print("calling class method: \(method_name) on \(targeted_cls), \(type_encoding)")
                let n = call_objc_class(L, mtd, targeted_cls)

                return n
            }

            /*if matched_cls != meta_class {
                // TODO: may search up the meta class chain for class method
                assert(false)
            }*/

            lua_pushcclosure(L, lua_func, 0) // meta, func
            lua_setfield(L, -2, method_name) // meta
            lua_pop(L, 1) // ^

            // ret
            lua_pushcclosure(L, lua_func, 0)
        }

        /*if let (mtd, matched_cls) = matchedSelector(cls, method_name) {
            print("found class method (non-meta): \(method_name) \(mtd) on \(matched_cls)")
            push_func(mtd, matched_cls)
            return 1
        }*/

        if let (mtd, matched_cls) = matchedSelector(meta_classes, method_name) {
            print("found class method: \(method_name) \(mtd) on \(matched_cls)")
            push_func(mtd, cls)

            return 1
        } else {
            print("not found class method: \(method_name) in \(methodNames(meta_class).count) methods of \(T.self)")
            assert(false)
            return 0
        }
    }
}

private func collectOn<T>(class: AnyClass, access: (AnyClass?, UnsafeMutablePointer<UInt32>?) -> UnsafeMutablePointer<T>?) -> [T] {
    var all = [T]()
    withClass(class: `class`, access: access) { t in
        all.append(t)
        return false
    }

    return all
}

private func withMethods(_ cls: AnyClass, _ call: (_ method: Method) -> Bool) {
    withClass(class: cls, access: class_copyMethodList, call: call)
}

private func withProperties(_ cls: AnyClass, _ call: (_ prop: objc_property_t) -> Bool) {
    withClass(class: cls, access: class_copyPropertyList, call: call)
}

public func methodNames(_ cls: AnyClass) -> [String] {
    return methodSelectors(cls).map {NSStringFromSelector($0)}
}

public func methodSelectors(_ cls: AnyClass) -> [Selector] {
    return collectOn(class: cls, access: class_copyMethodList).map { mtd in
        return method_getName(mtd)
    }
}

private func propertyNames(_ cls: AnyClass) -> [String] {
    let names = collectOn(class: cls, access: class_copyPropertyList).map { prop in
        return String(utf8String: property_getName(prop))!
    }
    return names
}

private func isRoot(_ cls: AnyClass) -> Bool {
    return cls.description() == "SwiftObject" || cls == NSObject.self
}

public func withSupers(_ cls: AnyClass) -> [AnyClass] {
    print("supers for \(cls)")
    var classes = [AnyClass]()
    var cur: AnyClass = cls
    while (class_isMetaClass(cur) == false) {
        classes.append(cur)
        print("-- \(String(describing: cur))")

        if isRoot(cur) {
            break
        }
        cur = class_getSuperclass(cur)!
    }

    return classes
}

private func isEqualToSelector(_ src: String, _ sel: String) -> Bool {
    let cand = selectorCandidates(src)
    return cand.0 == sel || cand.1 == sel
}

private func selectorCandidates(_ src: String) -> (String, String) {
    let rep = src.replacingOccurrences(of: "_", with: ":")
    return (rep, rep + ":")
}

private func matchedSelector(_ classes: [AnyClass], _ selName: String) -> (Method, AnyClass)? {
    var matched: Method? = nil

    let checks = classes // class_isMetaClass(cls) ? [cls] : withSupers(cls)
    print("find selector \(selName) in classes: \(checks)")
    for cls in checks {
        withMethods(cls) { mtd in
            let sel = method_getName(mtd)
            let name = NSStringFromSelector(sel)
            if isEqualToSelector(selName, name) {
                matched = mtd
                return true
            }
        
            return false
        }
        if matched != nil {
            return (matched!, cls)
        } else {
            print("failed to find '\(selName)' in all methods for \(cls)") //": \(methodNames(cls))")
        }
    }
    return nil
}
