//
//  Args.swift
//  SwiftyLua
//
//  Created by hanzhao on 2017/2/12.
//  Copyright © 2017年 hanzhao. All rights reserved.
//

import Foundation
import LuaSource

private let print = Logger.genPrint(level: .args)
private let t_print = Logger.genTPrint(print)

let YES = 1
let NO = 0

func args_to<A>(_ args: Any) -> A {
    if let a = args as? A {
        return a
    }
    var local_args = args
    var pt: A!
    withUnsafePointer(to: &local_args) {ptr in
        let c_ptr = UnsafeRawPointer(ptr)
        // print("address: \(addr) -> \(String(describing: c_ptr)), \(args) of type \(type(of: args)) to: \(A.self)")

        pt = c_ptr.bindMemory(to: A.self, capacity: 1).pointee
    }
    return pt
}

public enum Kind {
    case string
    case number
    case boolean
    case function
    case table
    case userdata
    case lightUserdata
    case thread
    case `nil`
    case none

    internal func luaType() -> Int32 {
        switch self {
        case .string: return LUA_TSTRING
        case .number: return LUA_TNUMBER
        case .boolean: return LUA_TBOOLEAN
        case .function: return LUA_TFUNCTION
        case .table: return LUA_TTABLE
        case .userdata: return LUA_TUSERDATA
        case .lightUserdata: return LUA_TLIGHTUSERDATA
        case .thread: return LUA_TTHREAD
        case nil: return LUA_TNIL

        case .none:
            fallthrough
        default:
            return LUA_TNONE
        }
    }
}

public struct ArgLoader {
    private var meta_map: MetaMap
    private var block_map: Ref<BlockMap>
    init(_ meta: MetaMap, _ blockMap: Ref<BlockMap>) {
        self.meta_map = meta
        self.block_map = blockMap
    }

    internal func kind(_ L: L_STATE, _ pos: Int) -> Kind {
        switch lua_type(L, Int32(pos)) {
        case LUA_TSTRING: return .string
        case LUA_TNUMBER: return .number
        case LUA_TBOOLEAN: return .boolean
        case LUA_TFUNCTION: return .function
        case LUA_TTABLE: return .table
        case LUA_TUSERDATA: return .userdata
        case LUA_TLIGHTUSERDATA: return .lightUserdata
        case LUA_TTHREAD: return .thread
        case LUA_TNIL: return .nil
        default: return .none
        }
    }

    func genOpt<T>() -> T? {
        let size = MemoryLayout<T>.size
        let ptr = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 0)
        memset(ptr, 0, size)

        return nil
    }

    func load<T>(_ L: L_STATE) -> T {
        t_print("load arg: \(T.self)")

        if T.self == Void.self {
            return () as! T
        }
        let v: T = load_opt(L)
        return v
    }
    
    // push super meta of meta at index
    private func super_meta(_ L: L_STATE, at index: Int32, for class: String) {
        lua_getmetatable(L, index) // meta, another_meta
        assert(lua_istable(L, -1))
        
        lua_getfield(L, -1, "class_meta") // is it class_meta?
        if lua_isstring(L, -1) {
            let meta_name = lua_tostring(L, -1)
            lua_pop(L, 1)
            
            print("chasing super for \(meta_name)")
            lua_getmetatable(L, -1) // get super
            
            if lua_istable(L, -1) {
                lua_getfield(L, -1, "__name") // meta, class_meta, super_meta, name
                let super_name = lua_tostring(L, -1)
                lua_pop(L, 1) // meta, class_meta, super_meta
                
                lua_remove(L, -2) // meta, super_meta
                
                assert(super_name == `class`)
            } else {
                assert(false)
            }
        } else {
            assert(lua_isnil(L, -1))
            lua_pop(L, 1)
        }
    }
    
    // NSData is presented in swift as Data which is Foundation._DataStorage backed
    // @ref: https://github.com/apple/swift-corelibs-foundation/blob/master/Foundation/Data.swift
    private func implicitlyConvertable(from received: String, to expected: String) -> Bool {
        return received == "ImplicitlyUnwrappedOptional<\(expected)>"
    }
    
    func load_opt<T>(_ L: L_STATE) -> T {
        // print("top: \(kind(L, -1))")
        var val: Any!

        if let loader = meta_map.loader(of: T.self) {
            let val = loader(L, -1, self)
            lua_pop(L, 1)
            return val as! T
        }
        // print_stack(L, "load opt")
        switch kind(L, -1) {
        case .number, .string, .boolean:
            // should be registered and catch above
            print("failed to catch: \(T.self) \(MemoryLayout<T>.size)")
            assert(false)
        
        case .table:
            if lua_getmetatable(L, -1) == 1 {
                // {} - meta
                lua_pushstring(L, "__name") // {} - meta - __name
                lua_rawget(L, -2) // {} - meta - name

                if lua_isstring(L, -1) == 1 {
                    let meta_name = lua_tostring(L, -1)
                    // print("meta is: \(meta_name)")
                    lua_pop(L, 1) // {} - meta

                    // type check
                    // var matched_class = false
                    var caster: MetaMap.Caster? = nil
                    let t_name = "\(T.self)"
                    if meta_name != t_name {
                        print("type mismatch for arg \(meta_name) != \(T.self), considering a casting?")
                        
                        // if t_name != "ImplicitlyUnwrappedOptional<\(meta_name)>" {
                        if implicitlyConvertable(from: t_name, to: meta_name) == false {
                        
                            if is_ref(T.self) {
                                // reaching for supers to see if there's a match
                                // lua_getmetatable(L, -1)
                                super_meta(L, at: -1, for: t_name)
                                if lua_istable(L, -1) { // {} - meta - super_meta
                                    lua_pushstring(L, "__name")
                                    lua_rawget(L, -2) // {} - meta - super_meta - __name
                                    let super_name = lua_tostring(L, -1)
                                    if super_name == t_name {
                                        lua_pop(L, 2)
                                        caster = meta_map.caster("\(meta_name) -> \(t_name)")
                                        // matched_class = true
                                    } else {
                                        print("find super as: \(super_name), not expected for \(t_name), passing in the wrong obj?")
                                        assert(false)
                                    }
                                } else {
                                    print("no super registered for \(t_name), may need reach up futher")
                                    assert(false)
                                }
                            }
                        } else {
                            print("ImplicitlyUnwrappedOptional type: \(meta_name)")
                        }
                    }

                    lua_pop(L, 1) // {}

                    // lua_getfield(L, -1, "__swift_obj") // {} - swift_ptr
                    lua_pushstring(L, "__swift_obj")
                    lua_rawget(L, -2)
                    
                    assert(lua_isuserdata(L, -1) == 1)
                    let u_len = lua_rawlen(L, -1) // length of userdata
                    let obj_ptr = lua_touserdata(L, -1)!

                    // print("swift obj is: \(obj_ptr), len: \(u_len), T is: \(T.self) \(sizeof(T.self))")
                    if u_len == sizeof(T.self) {
                        let obj = obj_ptr.bindMemory(to: T.self, capacity: 1)
                        print("after bind: \(obj)") //", \(obj.pointee), \(bytes(of: obj))")
                        print("pointee: \(bytes(of: obj.pointee)) \(hex(obj.pointee))")
                        lua_pop(L, 2)

                        return obj.pointee
                    } else if u_len == 0 {
                        // light user data passing as reference?
                        lua_pushstring(L, "__passing_style") // {}, swift_ptr, __passing_style
                        lua_rawget(L, -3) // {}, swift_ptr, by_reference?
                        let style = lua_isnil(L, -1) ? "N/A" : lua_tostring(L, -1)
                        lua_pop(L, 1) // {}, swift_ptr
                        
                        if style == ArgPassingStyle.byReference.rawValue {
                            let obj: T = dereference(obj_ptr)
                            lua_pop(L, 2)
                            
                            return obj
                        } else {
                            assert(false)
                        }
                        
                    } else if caster != nil {
                        let casted = caster!(obj_ptr)
                        print("casted to \(casted), expecting type: \(T.self)")
                        lua_pop(L, 2)

                        return casted as! T
                    } else {
                        // size mismatch, T -> Optional<T>
                        let size = sizeof(T.self)
                        let buf = UnsafeMutableRawPointer.allocate(byteCount: u_len, alignment: 0)
                        memset(buf, 0, sizeof(T.self))
                        print("buf: \(hex(content(buf, size))), orig ptr: \(hex(content(obj_ptr, u_len)))")

                        memcpy(buf, obj_ptr, u_len)
                        // !!! print("after cpy, buf: \(hex(content(buf, size))), orig ptr: \(hex(content(obj_ptr, u_len)))")
                        buf.storeBytes(of: 0, toByteOffset: size - 1, as: UInt8.self)
                        // print("last byte, buf: \(hex(content(buf, size))), orig ptr: \(hex(content(obj_ptr, u_len)))")

                        let obj = obj_ptr.bindMemory(to: T.self, capacity: 1)
                        // print("binded: \(hex(content(obj, u_len)))")
                        // print("\(u_len) \(hex(obj.pointee)))")

                        // print_stack(L)
                        var v = obj.pointee
                        // print("\(u_len) \(hex(v))")
                        lua_pop(L, 2)
                        buf.deallocate() // (bytes: size, alignedTo: 0)

                        // need to enforce the last byte, for the v = obj.pointee seems scratch the last byte sometimes
                        withUnsafeMutableBytes(of: &v) { ptr in
                            ptr.storeBytes(of: 0, toByteOffset: size - 1, as: UInt8.self)
                        }

                        // print("\(u_len) \(hex(v))")
                        return v
                    }
                } else {
                    print_stack(L, .args)
                    assert(lua_isnil(L, -1))
                    assert(false)
                }

            } else {
                // plain table

                // check if it's an array
                if table_is_array(L, -1) {
                    // array, should registered as [T]
                    print("loading array \(T.self)")
                    assert(false)
                } else {
                    // dictionary
                    assert(false)
                }
            }
            
            break
        case .function:
            let key = String(describing: T.self)
            let (is_opt, mapped) = key.check(.Optional)

            var blk = block_map.val[is_opt ? mapped! : key] ?? block_map.val[key]

            // cast to block generator -> T (with args)
            let gen: (L_STATE) -> T = casting(&blk)
            val = gen(L)
            
        case .userdata:
            let t_name = String(describing: T.self)
            print("userdata of: ", t_name)
            let (is_opt, type) = t_name.check(.Optional)
            lua_getglobal(L, is_opt ? type : t_name) // ud, meta
            if lua_istable(L, -1) {
                // enum enforcement
                lua_getfield(L, -1, "__note")
                assert(lua_isstring(L, -1) == 1) // ud, meta, enum?

                if lua_tostring(L, -1) == "enum" {
                    lua_pop(L, 2) // ud
                    // copy back
                    let ud = lua_touserdata(L, -1)!
                    let binded = ud.bindMemory(to: T.self, capacity: 1)
                    val = binded.pointee

                    break
                }
            }
            assert(false)
        case .lightUserdata:
            assert(false)
        case .thread:
            assert(false)
        case .nil:
            let size = MemoryLayout<T>.size
            let ptr = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 0)
            memset(ptr, 0, size)

            let obj = ptr.bindMemory(to: T.self, capacity: 1)
            let disp = Mirror(reflecting: obj.pointee).displayStyle
            if disp == .optional {
                if size % 2 != 0 {
                    // should be a value type, set last byte to 1 (Optional<T>'s memory layout when T is a struct)
                    ptr.storeBytes(of: 1, toByteOffset: size - 1, as: UInt8.self)
                }

                print("mirror of optional is: \(Mirror(reflecting: obj.pointee)), \(bytes(of: obj.pointee))")

                val = obj.pointee
                
                ptr.deallocate()
            } else {
                assert(false)
            }

        default:
            print_stack(L, .args)
            assert(false)
        }

        lua_pop(L, 1)
        return val as! T
    }
}
