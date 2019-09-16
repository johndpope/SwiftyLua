//
//  Utility.swift
//  SwiftyLua
//
//  Created by hanzhao on 2017/2/12.
//  Copyright © 2017年 hanzhao. All rights reserved.
//

import Foundation
import LuaSource

class Box<T> {
    public let unboxed: T
    public init (_ v: T) { self.unboxed = v }
    deinit {
        print("boxed \(unboxed) is dtor")
    }
}

extension String {
    func substring(to: Int) -> String {
        // return substring(to: self.index(self.startIndex, offsetBy: to))
        return String(self[...self.index(self.startIndex, offsetBy: to)])
    }
}

func abbr(_ o: Any, _ len: Int = 100) -> String {
    let desc = "\(o)"
    if desc.count > len {
        return desc.substring(to: len) + "... (\(desc.count - len) omitted)"
    }
    return desc
}

extension Thread {
    public var id: String {
        get {
            // <NSThread: 0x170872340>{number = 4, name = (null)}
            let desc = String(describing: self)

            let matches = desc.matchingStrings(regex: "number = (\\d+),")
            // print("tid: \(desc) -> \(matches)")
            return matches[0][1]
        }
    }

    @objc public func getId() -> String {
        return self.id
    }
}

public func t_print(_ args: Any...) {
    print("[\(Thread.current.id)]", args)
}

func on_main(wait: Bool, _ block: @escaping ()->()) {
    if wait {
        let cond = NSCondition()

        let id = Thread.current.id
        t_print("exec for block on - \(id)")
        var done = false
        DispatchQueue.main.async {
            block()

            cond.lock()
            t_print("block done on main - \(id)")
            done = true
            cond.signal()
            cond.unlock()
        }

        cond.lock()
        t_print("wait signal - \(id)")
        while !done {
            cond.wait()
        }
        t_print("signal triggered - \(id)")
        cond.unlock()
    } else {
        DispatchQueue.main.async {block()}
    }
}

class Ref<T> {
    var val: T

    init(_ v: T) {
        val = v
    }
}

extension Mirror {
    func subject(withModule: Bool) -> String {
        let desc = "\(self.subjectType)"
        if let range = desc.range(of: ".") {
            // return desc.substring(from: range.upperBound)
            return String(desc[range.upperBound...])
        } else {
            return desc
        }
    }
}

extension String {
    enum Pattern: String {
        case Array = "Array<(.+)>"
        case Optional = "Optional<(.+)>"
    }

    func matchingStrings(regex: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: regex, options: []) else { return [] }
        let nsString = self as NSString
        let results  = regex.matches(in: self, options: [], range: NSMakeRange(0, nsString.length))
        return results.map { result in
            (0..<result.numberOfRanges).map { result.range(at: $0).location != NSNotFound
                ? nsString.substring(with: result.range(at: $0))
                : ""
            }
        }
    }

    func check(_ pattern: Pattern) -> (Bool, String?) {
        let matched = matchingStrings(regex: pattern.rawValue)
        if (matched.count > 0) {
            return (true, matched[0][1])
        } else {
            return (false, nil)
        }
    }
}

extension Mirror.DisplayStyle {
    var name: String {get {
        switch self {
        case .class:
            return "class"
        case .struct:
            return "struct"
        case .enum:
            return "enum"
        case .collection:
            return "collection"
        case .dictionary:
            return "dictionary"
        case .optional:
            return "optional"
        case .set:
            return "set"
        case .tuple:
            return "tuple"
        }
        }}
}

func is_ref<T>(_ t: T) -> Bool {
    // some complex struct can't use MemoryLayout to deduce (e.g. DropboxDiskService)
    let type_size = MemoryLayout<T>.size
    let opt_size = MemoryLayout<T?>.size
    return type_size == opt_size
    // return T.self is AnyClass
}

func is_ref<T>(_ t: T.Type) -> Bool {
    return MemoryLayout<T>.size == MemoryLayout<T?>.size
}

func is_class<T>(_ t: T.Type) -> Bool {
    return T.self is AnyClass
}

func is_val<T>(_ t: T) -> Bool {
    return !is_ref(t)
}

func casting<T, U>(_ t: inout T) -> U {
    var u_ptr: UnsafePointer<U>!
    withUnsafePointer(to: &t) { ptr in
        let raw_ptr = UnsafeRawPointer(ptr)
        u_ptr = raw_ptr.bindMemory(to: U.self, capacity: 1)
    }

    return u_ptr.pointee
}

func to_ptr<T>(_ t: inout T) -> UnsafeMutableRawPointer {
    var raw_ptr: UnsafeMutableRawPointer!
    withUnsafePointer(to: &t) { ptr in
        raw_ptr = UnsafeMutableRawPointer(mutating: ptr)
    }
    return raw_ptr
}

func as_cfunc(_ method: @escaping (L_STATE) -> Int32) -> lua_CFunction {
    let f_wrapper: @convention(block) (L_STATE) -> Int32 = method
    
    let block: AnyObject = unsafeBitCast(f_wrapper, to: AnyObject.self)
    let imp = imp_implementationWithBlock(block)
    
    let lua_cfp = unsafeBitCast(imp, to: lua_CFunction.self)
    
    return lua_cfp
}

func as_kfunc(_ method: @escaping (L_STATE, Int32, lua_KContext) -> Int32) -> lua_KFunction {
    let f_wrapper: @convention(block) (L_STATE, Int32, lua_KContext) -> Int32 = method
    let block: AnyObject = unsafeBitCast(f_wrapper, to: AnyObject.self)
    let imp = imp_implementationWithBlock(block)
    
    let lua_cfp = unsafeBitCast(imp, to: lua_KFunction.self)
    
    return lua_cfp
}

public func sizeof <T> (_ : T.Type) -> Int
{
    return (MemoryLayout<T>.size)
}

func sizeof <T> (_ : T) -> Int
{
    return (MemoryLayout<T>.size)
}


func error_function(_ L: L_STATE) -> Int32 {
    let error_msg = lua_tostring(L, 1)
    luaL_traceback(L, L, "traceback", 0)
    let trace = lua_tostring(L, 2)
    lua_pop(L, 2)

    lua_pushstring(L, error_msg + "/n" + trace)

    return 1
}

func synced(_ lock: Any, closure: () -> ()) {
    objc_sync_enter(lock)
    closure()
    objc_sync_exit(lock)
}

private func stack_of(_ L: L_STATE, _ msg: String = "") -> String {
    let top = lua_gettop(L)
    var stack = "--- \(top) \(msg)---\n"
    if top > 0 {
        for i in 1 ... top {
            stack += "\(i): "
            stack += stack_item(L, Int(i))

            stack += "\n"
        }

        stack += "--- top ---\n"
    } else {
        stack += "empty stack"
    }

    return stack
}

public func print_stack(_ L: L_STATE, _ msg: String = "") {
    print("[" + Thread.current.id + "]", stack_of(L, msg))
}

func stack_item(_ L: L_STATE, _ i: Int, _ expandTable: Bool = true) -> String {
    let t = lua_type(L, Int32(i))
    var cat = "(" + String(cString: lua_typename(L, t)!) + ") "

    switch (t) {
    case LUA_TSTRING:
        cat += lua_tostring(L, i)
    case LUA_TBOOLEAN:
        cat += (lua_toboolean(L, Int32(i)) == 1 ? "true" : "false")
    case LUA_TNUMBER:
        cat += ("\(lua_tonumber(L, i))")
    case LUA_TTABLE:
        cat += ("\(String(describing: lua_topointer(L, Int32(i))))\n")
        if expandTable {
            cat += " {\n"
            cat += table_item(L, i)
            cat += " }\n"
        }
    default:
        cat += ("\(String(describing: lua_topointer(L, Int32(i))))")
    }
    return cat
}

func table_itor(_ L: L_STATE, _ i: Int, each: (_ L: L_STATE, _ n: Int32) -> Bool) {

    lua_pushnil(L);  // {}, first key
    while (lua_next(L, Int32(i - 1)) != 0) {
        // {}, key, val
        if each(L, Int32(i - 2)) {
            // stop
            break
        }
        lua_pop(L, 1)
    }
}

// check if a table is an array
// @ref: http://stackoverflow.com/questions/7526223/how-do-i-know-if-a-table-is-an-array
func table_is_array(_ L: L_STATE, _ n: Int) -> Bool {
    assert(lua_type(L, n) == LUA_TTABLE)

    var is_arr = true
    var i = 1
    table_itor(L, n) { L, at in
        // key, val
        let type = lua_geti(L, at, lua_Integer(i))
        // just need the type
        lua_pop(L, 1)

        if type == LUA_TNIL {
            // found a hole
            is_arr = false
            // stop
            return true
        }
        i = i + 1
        return false
    }

    return is_arr
}

func table_item(_ L: L_STATE, _ i: Int) -> String {
    var cat = ""
    // table is in the stack at index 't'
    var t = i

    if (t < 0) {
        t = Int(lua_gettop(L)) + t + 1; // if t is negative, we need to normalize
    }
    if (t <= 0 || t > Int(lua_gettop(L))) {
        print("\(t) is not within stack boundries");
        return cat;
    }
    else if (!lua_istable(L, t)) {
        print("Object at stack index \(t) is not a table");
        return cat;
    }

    lua_pushnil(L);  // first key
    while (lua_next(L, Int32(t)) != 0) {
        cat += stack_item(L, -2)
        cat += " : "
        cat += stack_item(L, -1, false) + ",\n"

        lua_pop(L, 1); // remove 'value'; keeps 'key' for next iteration
    }
    return cat
}

public func debug_info(_ L: L_STATE) -> String {
    var msg = "~ debug ~\n"
    var level: Int32 = 0
    var info = lua_Debug()
    withUnsafeMutablePointer(to: &info) { ptr in
        let info = ptr.pointee
        while lua_getstack(L, level, ptr) == LUA_OK {
            msg += ("[\(level)] \(String(describing: info.source)):\(info.currentline) -- \(String(describing: info.name)), \(String(describing: info.what))")
            level += 1
        }
    }
    return msg + "- end -\n"
}
