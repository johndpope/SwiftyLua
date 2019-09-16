//
//  Return.swift
//  SwiftyLua
//
//  Created by hanzhao on 2017/2/12.
//  Copyright © 2017年 hanzhao. All rights reserved.
//

import Foundation
import LuaSource

private let print = Logger.genPrint(level: .return)
private let t_print = Logger.genTPrint(print)

func pointer<T>(of t: inout T) -> UnsafeMutableRawPointer {
    var c_ptr: UnsafeMutableRawPointer!
    withUnsafePointer(to: &t) { ptr in
        c_ptr = UnsafeMutableRawPointer(mutating: ptr)
    }
    return c_ptr
}

func address<T>(of t: inout T) -> UnsafeMutableRawPointer {
//    guard sizeof(t) == sizeof(Int()) else {
//        print("size of \(t) is: \(sizeof(t))")
//        assert(false)
//    }
//    let addr = unsafeBitCast(t, to: Int.self)
//    return UnsafeMutableRawPointer(bitPattern: addr)!
    return Unmanaged.passUnretained(t as AnyObject).toOpaque()
}

func dereference<T>(_ address: UnsafeMutableRawPointer) -> T {
    //let int_addr = Int(bitPattern: address)
    //return unsafeBitCast(int_addr, to: T.self)
    let ref = Unmanaged<AnyObject>.fromOpaque(address)
    let val = ref.takeUnretainedValue()
    return val as! T
}

func push_class<R>(_ L: L_STATE, _ ret: inout R, _ in_type: String?) {
    var v_ret = ret
    let type_name = in_type != nil ? in_type! : String(describing: type(of: ret))
    
    // created in lua?
    lua_getglobal(L, "__swift_reg") // reg

    let l_ret = address(of: &v_ret)
    lua_pushlightuserdata(L, l_ret) // reg, ret

    if lua_gettable(L, -2) == LUA_TTABLE { // reg, lua_obj
        switch lua_getfield(L, -1, "__swift_obj") { // reg, lua_obj, swift_obj
        case LUA_TUSERDATA, LUA_TLIGHTUSERDATA:
            lua_pop(L, 1) // reg, lua_obj
            lua_remove(L, -2) // lua_obj
            
            lua_getfield(L, -1, "__objc_type") // lua_obj, objc_type
            let objc_type = lua_tostring(L, -1)
            lua_pop(L, 1) // lua_obj
            // light userdata may get reused from the cocoa side
            if objc_type != type_name {
                print("type mismatch: ", objc_type, type_name)
                lua_pushstring(L, type_name) // lua_obj, type_name
                lua_setfield(L, -2, "__objc_type")
            }
            
            break
        default:
            assert(false)
        }

    } else {
        // not in reg, should return light userdata
        lua_pop(L, 2) // remove reg, ret
        
        create_luaobj(L, &ret, type_name, passing: .byReference)
    }
}

fileprivate func genCollection<R>(_ ret: R, _ typeName: String, _ L: L_STATE, _ meta_map: MetaMap, setter: (_ keyPusher: () -> (), _ valPusher: () -> ()) -> ()) {
    // may be too big to print

    let col_ref = Mirror(reflecting: ret)
    let type_name = String(describing: col_ref.subjectType)
    assert(type_name.range(of: ":") == nil)
    let col_inner = type_name.matchingStrings(regex: typeName + "<(.+)>")
    let inner_type = col_inner[0][1]

    lua_newtable(L) // {}
    for (i, v) in col_generator(ret).enumerated() {
        // print("pushing item: ", i, v)
        var vv = v
        // v is Any for enumberated value, Xcode 8.3.1 couldn't reflect to get the orignal type from Any
        // have to pass in the inner type
        // push_ret(L, &vv, meta_map, inner_type) // {}, vv
        // lua_seti(L, -2, Int64(i + 1)) // {[i+1] = vv}

        setter({lua_pushinteger(L, Int64(i + 1))}, {push_ret(L, &vv, meta_map, inner_type)})
        // assum: {}, key, val
        lua_rawset(L, -3)
    }
}

func check_bridge<R, B>(_ ret: inout R, _ b: B?.Type) -> B? {
    if R.self == B?.self {
        let casted: B? = casting(&ret)
        print("bridged is: ", casted ?? "invalid casting")
        return casted
    }
    return nil
}

@discardableResult
func push_ret<R>(_ L: L_STATE, _ ret: inout R, _ meta_map: MetaMap, _ in_type: String? = nil) -> Int {
    if let r = ret as? Ls {
        // prime types
        r.push(L)
        return 1
    } else if type(of: ret) == Void.self {
        // non
        return 0
    } /*else if let obj = ret as? NSObject {
        print("is NSObject: \(ret)")
        return 1
    } */ else {
        let reflect = Mirror(reflecting: ret)
        // ret might be too big to pring (array etc)
        // t_print("unsupported return type: \(type(of: ret)), reflection: \(reflect) \(String(describing: reflect.displayStyle)), size: \(sizeof(ret)), top \(lua_gettop(L))")

        switch reflect.displayStyle! {
        case .struct:
            // should always return a copy
            // var v_ret = ret
            let sub_name = reflect.subject(withModule: false)
            print("R is \(R.self), \(sub_name)")
            lua_getglobal(L, sub_name) // struct
            assert(lua_istable(L, -1))
            lua_getfield(L, -1, "__size")
            let struct_size = lua_tointeger(L, -1)
            assert(struct_size > 0)
            lua_pop(L, 2) // pop off: meta, size

            create_lua_struct_for_obj(L, &ret, sub_name, Int(struct_size))
            // let back = ptr.bindMemory(to: R.self, capacity: 1).pointee
            // print("back \(back)")

            break
        case .class:
            if R.self == Any.self {
                var ret_obj = ret as AnyObject
                push_class(L, &ret_obj, in_type)
            } else {
                push_class(L, &ret, in_type)
            }

        case .enum:
            // value obj
            print_stack(L, "pre enum");

            let len = MemoryLayout<R>.size
            assert(len > 0)
            let ud = lua_newuserdata(L, len) // ud

            let type_name = String(describing: R.self)
            lua_getglobal(L, type_name)
            assert(lua_istable(L, -1)) // ud, meta

            // set enum's meta
            lua_setmetatable(L, -2) // ud

            let _ = withUnsafeBytes(of: &ret) { ptr in
                memcpy(ud, ptr.baseAddress, len)
            }
            print_stack(L, "post enum")

        case .optional:
            // t_print("ret is, type: \(R.self): \(ret) \(hex(ret, reverse: true))")
            // assert(false)
            
            if (bytes(ret).allSatisfy {$0 == 0}) {
                lua_pushnil(L)
                return 1
            }
            
            if var data = check_bridge(&ret, Data?.self) {
                return push_ret(L, &data, meta_map)
            }
            
            if RefTrait<R>().isRef {

                if ret is NSObject {
                    t_print("is NSObject: \(ret)")
                    let type_name = String(describing: type(of: ret))

                    // unquote Optional<...> to get class name
                    if let prefix = type_name.range(of: "Optional<") {
                        let tail = type_name.index(type_name.endIndex, offsetBy: -1)
                        let unquoted = String(type_name[prefix.upperBound..<tail])

                        var casted = ret as! NSObject
                        push_class(L, &casted, unquoted)
                    } else {
                        assert(false)
                    }
                } else {
                    var v_ret = ret
                    // check nil
                    let addr: Int = casting(&v_ret)
                    if addr == 0 {
                         lua_pushnil(L)
                    } else {
                        guard meta_map.chasing(L, ret) else {
                            assert(false)
                            return 1
                        }
                    }
                }
            } else {
                let last_byte = byte(of: &ret, at: sizeof(R.self) - 1)
                if last_byte == 1 {
                    // it's a nil
                    lua_pushnil(L)
                } else {
                    guard meta_map.chasing(L, ret) else {
                        assert(false)
                        return 1
                    }
                }
            }
            break
        case .tuple:
            break
        case .collection:
            t_print("ret collection:")
            genCollection(ret, "Array", L, meta_map) { idx_pusher, val_pusher in
                idx_pusher() // {}, idx
                val_pusher() // {}, idx, val
            }
            t_print("all items pushed")
            break
        case .set:
            t_print("ret set:")
            genCollection(ret, "Set", L, meta_map) { idx_pusher, val_pusher in
                val_pusher() // {}, val
                lua_pushboolean(L, 1) // {}, val, true
            }
            t_print("set items pushed")
        case .dictionary:
            assert(false)
        }
        return 1
    }
}

