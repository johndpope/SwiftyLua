//
//  ObjC.swift
//  SwiftyLua
//
//  Created by hanzhao on 2017/3/27.
//  Copyright © 2017年 hanzhao. All rights reserved.
//

import Foundation
import ObjectiveC.runtime

let _C_ID = "@"
let _C_CLASS = "#"
let _C_SEL = ":"
let _C_CHR = "c"
let _C_UCHR = "C"
let _C_SHT = "s"
let _C_USHT = "S"
let _C_INT = "i"
let _C_UINT = "I"
let _C_LNG = "l"
let _C_ULNG = "L"
let _C_LNG_LNG = "q"
let _C_ULNG_LNG = "Q"
let _C_FLT = "f"
let _C_DBL = "d"
let _C_BFLD = "b"
let _C_BOOL = "B"
let _C_VOID = "v"
let _C_UNDEF = "?"
let _C_PTR = "^"
let _C_CHARPTR = "*"
let _C_ATOM = "%"
let _C_ARY_B = "["
let _C_ARY_E = "]"
let _C_UNION_B = "("
let _C_UNION_E = ")"
let _C_STRUCT_B = "{"
let _C_STRUCT_E = "}"
let _C_VECTOR = "!"
let _C_CONST = "r"

func method_getArgumentType(_ mtd: Method, _ idx: UInt32) -> String {
    let len = 10
    let buf = UnsafeMutablePointer<Int8>.allocate(capacity: len)
    method_getArgumentType(mtd, UInt32(idx), buf, len)

    return String(validatingUTF8: UnsafePointer<CChar>(buf))!
}

func method_getReturnType(_ m: Method) -> String {
    let len = 10
    let buf = UnsafeMutablePointer<Int8>.allocate(capacity: len)
    method_getReturnType(m, buf, len)

    return String(validatingUTF8: UnsafePointer<CChar>(buf))!
}

func with_protocol_method(_ proto: Protocol, _ cb: (Selector) -> ()) {
    [(true, true), (true, false), (false, true), (false, false)].forEach { (is_req, is_inst) in
        var n: UInt32 = 0

        let methods = protocol_copyMethodDescriptionList(proto, is_req, is_inst, &n)

        print("n: \(n), is required \(is_req), is instance \(is_inst)")
        var method = methods
        for _ in 0..<n {
            if let slot = method?.pointee {
                // print("adding protocol method: \(slot): \(slot.name) \(slot.types)")
                cb(slot.name!)

                method = method?.successor()
            }
        }
        free(methods)
    }
}

func protocol_methods(_ proto: Protocol) -> Set<Selector> {
    var methods = Set<Selector>()
    with_protocol_method(proto) { m in
        methods.insert(m)
    }
    return methods
}

func protocols_of(_ cls: AnyClass) -> [Protocol] {
    var n_proto: UInt32 = 0
    let protos = class_copyProtocolList(cls, &n_proto)!
    var rslt = [Protocol]()
    (0..<n_proto).forEach {i in
        rslt.append(protos[Int(i)])
    }

    return rslt
}

func protocol_methods(_ protos: [Protocol]) -> Set<Selector> {
    return Set(protos.map { p in
        return protocol_methods(p)
    } .flatMap { arr in
        return arr.map {$0}
    })
}

func class_methods(_ cls: AnyClass) -> Set<Selector> {
    let class_methods = withSupers(cls).map { c in
        return methodSelectors(c)
        } .flatMap { arr in
            return arr.map {$0}
    }
    return Set(class_methods)
}
