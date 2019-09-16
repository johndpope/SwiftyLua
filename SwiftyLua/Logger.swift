//
//  Logger.swift
//  SwiftyLua
//
//  Created by hanzhao on 2017/9/10.
//  Copyright © 2017年 hanzhao. All rights reserved.
//

import Foundation

@objc
public enum LogLevel: Int, CaseIterable {
    case none = 0
    case create = 1
    case `return` = 0x02
    case expose = 0x04
    case args = 0x08
    case lab = 0x10
    case `class` = 0x20
    case trait = 0x40
    case bridge = 0x100
    case objc = 0x2000

    static var all: Int {
        get {
            return LogLevel.allCases.reduce(0, {rslt, level in
                return rslt | level.rawValue
            })
        }
    }
    
    // static let none = 0
}

public class Logger: NSObject {
    @objc static public var level: Int = LogLevel.all //LogLevel.none.rawValue

    static public func genPrint(level local: LogLevel) -> (Any...) -> () {
        // print("log level: \(level)")
        return { (_ args: Any...) in
            if level & local.rawValue != 0 {
                let output = args.map {"\($0)"} .joined(separator: ", ")
                Swift.print(output)
            }
        }
    }

    static public func genTPrint(_ p: @escaping (Any...) -> ()) -> (Any...) -> () {
        return { (_ args: Any...) in
            p("[\(Thread.current.id)]", args)
        }
    }
}

public func print_stack(_ L: L_STATE, _ level: LogLevel, _ msg: String = "") {
    if Logger.level & level.rawValue != 0 {
        print_stack(L, msg)
    }
}
