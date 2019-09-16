//
//  Lab.swift
//  SwiftyLua
//
//  Created by hanzhao on 2017/2/12.
//  Copyright © 2017年 hanzhao. All rights reserved.
//

import Foundation
import LuaSource

private let print = Logger.genPrint(level: .lab)
private let t_print = Logger.genTPrint(print)

struct RefTrait<T> {
    var isRef: Bool {
        let is_obj = (MemoryLayout<T>.size == MemoryLayout<T?>.size)
        let is_ptr = (MemoryLayout<T>.size == MemoryLayout<UnsafeRawPointer>.size)

        if is_obj != is_ptr {
            print("\(T.self), \(MemoryLayout<T>.size) == \(MemoryLayout<UnsafeRawPointer>.size)?")
        }

        return is_obj
        // return T.self is AnyClass
    }
}

struct InfNext {
    var magic: Int = 0
    var placeholder_0: Int = 0
    var placeholder_1: Int = 0
    var ptr = UnsafeRawPointer(bitPattern: 0)
}

public struct InfAny {
    var data_0 = UnsafeRawPointer(bitPattern: 0)
    var data_1 = UnsafeRawPointer(bitPattern: 0)
    var data_2 = UnsafeRawPointer(bitPattern: 0)
    var type_ptr = UnsafeRawPointer(bitPattern: 0)
}

open class MetaMap {
    public typealias Loader = (L_STATE, Int, ArgLoader) -> Any
    public typealias Pusher = (L_STATE, UnsafeRawPointer) -> ()
    public typealias Caster = (UnsafeMutableRawPointer) -> AnyObject
    class VTbl {
        var loader: Loader?
        var pusher: Pusher?

        init(loader: Loader? = nil, pusher: Pusher? = nil) {
            self.loader = loader
            self.pusher = pusher
        }
    }

    private var L: L_STATE
    private var map = [UnsafeRawPointer : VTbl]()
    private var casters = [String : Caster]()

    public init(_ L: L_STATE) {
        self.L = L
    }

    public func loader<T>(of t: T.Type) -> Loader? {
        return self.vtbl(t)?.loader
    }

    public func pusher<T>(of t: T.Type) -> Pusher? {
        return self.vtbl(t)?.pusher
    }

    private func vtbl<T>(_ t: T.Type) -> VTbl? {
        var tt = t
        let type_ptr: UnsafeRawPointer = casting(&tt)
        return map[type_ptr]
    }

    /*private func load<T>(_ L: L_STATE, _ t: T.Type, _ idx: Int) -> (Bool, Any?) {
        var tt = t
        let type_ptr: UnsafeRawPointer = casting(&tt)
        if let loader = map[type_ptr]?.loader {
            return (true, loader(L, idx))
        } else {
            return (false, nil)
        }
    }*/

    public func regCaster<T, S>(_ t: T.Type, _ s: S.Type) where T: AnyObject {
        casters["\(t) -> \(s)"] = { ptr in
            let binded = ptr.bindMemory(to: T.self, capacity: 1)
            return binded.pointee
        }
    }

    public func caster(_ key: String) -> Caster? {
        return casters[key]
    }
    public func regLoader<T>(_ t: T.Type) {
        // assert(false)
    }

    public func regLoader<T: Ls>(_ t: T.Type) {
        withLoader(t) {(L: L_STATE, idx: Int, argLoader: ArgLoader) in
            return T.load(L, idx)
        }
    }

    public func regLoader<T: Ls>(_ t: T?.Type) {
        withLoader(t) {(L: L_STATE, idx: Int, argLoader: ArgLoader) in
            if lua_isnil(L, idx) {
                return nil
            } else {
                return T.load(L, idx)
            }
        }
    }

    public func regLoader<T>(_ t: [T].Type) {
        // var tt = t
        // let type_ptr: UnsafeRawPointer = casting(&tt)

        withLoader(t) { (L: L_STATE, idx: Int, argLoader: ArgLoader) in
            var arr = [T]()
            let n = lua_objlen(L, idx)
            if n > 0 {
                for i in 1...n {
                    lua_geti(L, Int32(idx), lua_Integer(i))
                    let val:T = argLoader.load_opt(L)
                    arr.append(val)
                }
            }
            // print("arr is: \(arr)")
            return arr
        }
    }

    public func regLoader<K, V>(_ t: [K : V].Type) {
        assert(false)
    }

    public func regNSRefPusher(_ type_ptr: UnsafeRawPointer) {
        let pusher = { [unowned self] (L: L_STATE, buf: UnsafeRawPointer) in
            var v_buf = buf
            var pointee: NSObject = casting(&v_buf)
            push_ret(L, &pointee, self)
        }

        if let tbl = map[type_ptr] {
            tbl.pusher = tbl.pusher ?? pusher
        } else {
            let tbl = VTbl(loader: nil, pusher: pusher)
            map[type_ptr] = tbl
        }
    }

    public func regPusher<T>(_ t: T.Type) {
        var type = t
        let type_ptr: UnsafeRawPointer = casting(&type)

        let pusher = { [unowned self] (L: L_STATE, buf: UnsafeRawPointer) in
            t_print("pushing for \(t) \(Swift.type(of: t)) \(hex(buf)) \(sizeof(T.self)), top \(lua_gettop(L))")
            if RefTrait<T>().isRef {
                var v_buf = buf
                var pointee: T = casting(&v_buf)
                t_print("\(pointee)")
                push_ret(L, &pointee, self)
            } else {
                let binded = buf.bindMemory(to: T.self, capacity: 1)
                t_print("binded: \(binded) \(binded.pointee), top \(lua_gettop(L))")
                var pointee = binded.pointee
                push_ret(L, &pointee, self)
            }
        }

        if let tbl = map[type_ptr] {
            tbl.pusher = tbl.pusher ?? pusher
        } else {
            let tbl = VTbl(loader: nil, pusher: pusher)
            map[type_ptr] = tbl
        }
    }

    public func regPusher<K, V>(_ t: [K : V].Type) {
        var type = t
        let type_ptr: UnsafeRawPointer = casting(&type)

        let pusher = { (L: L_STATE, buf: UnsafeRawPointer) in
            t_print("pushing for \(t) \(Swift.type(of: t)) \(hex(buf)) \(sizeof([K : V].self)), top \(lua_gettop(L))")
            assert(false)
        }

        if let tbl = map[type_ptr] {
            tbl.pusher = tbl.pusher ?? pusher
        } else {
            let tbl = VTbl(loader: nil, pusher: pusher)
            map[type_ptr] = tbl
        }
    }

    public func chasing<T>(_ L: L_STATE, _ t: T) -> Bool {
        let reflect = Mirror(reflecting: t)
        switch reflect.displayStyle! {
        case .optional:
            if RefTrait<T>().isRef {
                var t_any = t as Any?
                let inf_any: InfAny = casting(&t_any)
                let binded = inf_any.data_0?.bindMemory(to: UnsafeRawPointer.self, capacity: 1).pointee

                if let pusher = self.map[binded!]?.pusher {
                    print("find pusher for: \(String(describing: inf_any.data_0)), top \(lua_gettop(L))")
                    pusher(L, inf_any.data_0!)

                    return true
                } else {
                    // has no registered pusher
                    print("binded: \(binded!) \(t)")
                    assert(false)
                }
            } else {
                return chasing_opt(L, t as Any?)
                // return chasing_typed_opt(L: L, t as Any?)
            }
        default:
            break
        }
        return false
    }

    // MARK: - helpers
    /*private func withLoader<T>(_ t: T?.Type, _ loader: @escaping (L_STATE, Int, ArgLoader) -> Any) {

    }*/

    private func withLoader<T>(_ t: T.Type, _ loader: @escaping (L_STATE, Int, ArgLoader) -> Any?) {
        var type = t
        let type_ptr: UnsafeRawPointer = casting(&type)

        if let tbl = map[type_ptr] {
            tbl.loader = tbl.loader ?? loader
        } else {
            let tbl = VTbl(loader: loader, pusher: nil)
            map[type_ptr] = tbl
        }
    }

    private func selectTypePtr(_ inf_any: InfAny) -> Dl_info?{
        let filtered = [inf_any.type_ptr, inf_any.data_0].map { ptr -> Dl_info in
            var dl_info = Dl_info()
            _ = dladdr(ptr, &dl_info)
            return dl_info
        } .filter { dl in
            return dl.dli_saddr != nil
        } .first

        return filtered
    }

    private func chasing_typed_opt<T>(L: L_STATE, _ t: T) -> Bool {
        var tt = t
        let vv: Any = casting(&tt)
        var tp = type(of: vv)
        print("chasing typed: ", tt, vv, tp)
        let type_ptr: UnsafeRawPointer = casting(&tp)

        if let pusher = self.map[type_ptr]?.pusher {
            let ptr: UnsafeRawPointer = casting(&tt)
            pusher(L, ptr)
            return true
        } else {
            assert(false)
        }

        return false
    }

    private func chasing_opt(_ L: L_STATE, _ t: Any?) -> Bool {
        let OPTIONAL_MAGIC = 3
        var tt = t
        let inf_any: InfAny = casting(&tt)
        t_print("casted: \(inf_any) \(type(of: t)), top \(lua_gettop(L))")

        let ptrs = [inf_any.type_ptr] //, inf_any.data_0]

        for type_ptr in ptrs {
            var ptr = type_ptr

            while ptr != nil {
                // pointing to meta class?
                var dl_info = Dl_info()
                let rslt = dladdr(ptr, &dl_info)
                if rslt != 0 {
                    let fname = String(cString: dl_info.dli_fname)
                    let sname = String(cString: dl_info.dli_sname)
                    t_print("found symbol \(dl_info) around \(String(describing: inf_any.type_ptr)): \(fname) \(sname)")

                    // try exact match
                    if let pusher = self.map[dl_info.dli_saddr]?.pusher {
                        t_print("find pusher for: \(String(describing: dl_info.dli_saddr)), top \(lua_gettop(L))")
                        pusher(L, inf_any.data_0!)

                        return true
                    } else {
                        assert(false)
                    }
                } else {
                    print("not found symbol for address: \(String(describing: inf_any.type_ptr)) \(String(describing: dlerror()))")
                }

                if let binded = ptr?.bindMemory(to: InfNext.self, capacity: 1).pointee {
                    if binded.magic == OPTIONAL_MAGIC {
                        t_print("chased ptr: \(String(describing: binded.ptr)), top \(lua_gettop(L))")
                        ptr = binded.ptr
                    } else {
                        t_print("chase ended")
                        break
                    }
                } else {
                    assert(false)
                }
            }
        }
        return false
    }
}


protocol LuaStackable {
    associatedtype Elem
    init(_ L: L_STATE)
}

protocol Listable {
    associatedtype Elem

    init(_ L: L_STATE, _ method: @escaping (Elem) -> ())
    func cons() -> Elem
}

/*
struct TypeList<H: LuaStackable, T: Listable>: Listable {
    typealias Elem = (H, T.Elem)

    var L: L_STATE
    internal init(_ L: L_STATE, _ method: @escaping (Elem) -> ()) {
        self.L = L
        print("mtd: \(type(of: method))")
    }

    func cons() -> Elem {
        print("ctor \(H.self), \(Elem.self)")
        let h: H = ArgLoader().load(L)
        return (h, T(L, { (t_elem: T.Elem) in
            print("dive in: \(T.Elem.self)")
        }).cons())
    }
}*/

public func byte<T>(of t: inout T, at index: Int) -> UInt8? {
    if index >= sizeof(T.self) {
        return nil
    } else {
        var byte: UInt8 = 0
        withUnsafeMutablePointer(to: &t) { ptr in
            let raw_ptr = UnsafeRawPointer(ptr) //(bitPattern: address(ptr))!
            byte = raw_ptr.load(fromByteOffset: index, as: UInt8.self)
        }
        return byte
    }
}

// @ref: https://realm.io/news/goto-mike-ash-exploring-swift-memory-layout/
public func bytes<T>(of value: T) -> [UInt8]{
    var value = value
    let size = MemoryLayout<T>.size
    return withUnsafePointer(to: &value, {
        $0.withMemoryRebound(
            to: UInt8.self,
            capacity: size,
            {
                Array(UnsafeBufferPointer(
                    start: $0, count: size))
        })
    })
}

public func content(_ ptr: UnsafeRawPointer, _ n: Int) -> [UInt8] {
    return (0..<n).map {
        return ptr.load(fromByteOffset: $0, as: UInt8.self)
    }
}

public func bytes<T>(_ t: T) -> [UInt8] {
    return bytes(of: t)
}

public func hex<T>(_ t: T, reverse: Bool = false) -> String {
    let arr = bytes(of: t)
    return hexString(bytes: reverse ? arr.reversed() : arr)
}

public func hex(_ t: [UInt8]) -> String {
    return hexString(bytes: t)
}

public func hexString<Seq: Sequence>
    (bytes: Seq, limit: Int? = nil, separator: String = " ")
    -> String
    where Seq.Iterator.Element == UInt8 {
        let spacesInterval = 8
        var result = ""
        for (index, byte) in bytes.enumerated() {
            if let limit = limit, index >= limit {
                result.append("...")
                break
            }
            if index > 0 && index % spacesInterval == 0 {
                result.append(separator)
            }
            result.append(String(format: "%02x", byte))
        }
        return result
}

func col_generator(_ col: Any) -> AnyIterator<Any> {
    return AnyIterator(Mirror(reflecting: col).children.lazy.map { $0.value }.makeIterator())
}

class Lab {

    struct EOF: Listable {
        typealias Elem = Void
        internal init(_ L: L_STATE,  _ method: @escaping (Elem) -> ()) {
            print("dive end: eof")
        }

        func cons() -> Elem {
            print("eof")
            return ()
        }
    }

    func generator_for_tuple(tuple: Any) -> AnyIterator<Any> {
        return AnyIterator(Mirror(reflecting: tuple).children.lazy.map { $0.value }.makeIterator())
    }
}
