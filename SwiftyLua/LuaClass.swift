//
//  LuaClass.swift
//  SwiftyLua
//
//  Created by hanzhao on 2017/2/26.
//  Copyright © 2017年 hanzhao. All rights reserved.
//

import Foundation
import LuaSource
import ObjectiveC.runtime

private let print = Logger.genPrint(level: .class)

extension NSObject {
    class func swiftClassFromString(className: String) -> AnyClass! {
        if let cls = NSClassFromString(className) {
            return cls
        }
        return NSClassFromString(LuaClass.frameworkName + "." + className)
    }
}

open class LuaClass {
    public static var L: L_STATE!
    public static var meta_map: MetaMap!
    public static let frameworkName = "SwiftyLua"
    
    private var my_class: AnyClass!
    private let type_name: String
    private let class_forwarder = ClassForwarder()

    public init(name: String, base: String, protocols: [String]) {
        print("creating class: \(name) => \(base) : \(protocols)")
        type_name = name

        guard let super_class = NSClassFromString(base) else {
            assert(false)
            return
        }

        let L = LuaClass.L!

        my_class = objc_allocateClassPair(super_class, name, 0)

        let protos = protocols.map {NSProtocolFromString($0)}
        protos.forEach {p in class_addProtocol(my_class, p!)}

        // forward to target
        class_addIvar(my_class, "__target", sizeof(ObjectForwarder.self), 0, "@")
        /*let attributes = [
            objc_property_attribute_t(name: "&", value: ""), // retain
            objc_property_attribute_t(name: "V", value: "__target"), // ivar
            objc_property_attribute_t(name: "T", value: "@"), // obj
            ]
        class_addProperty(my_class, "target", attributes, UInt32(attributes.count))
         */

        do {// forwardingTarget
            let forwarder: @convention(block) (AnyObject, Selector) -> NSObject = { [unowned self] (obj: AnyObject, sel: Selector) -> NSObject in
                print("forwarding \(obj), \(sel)")
                let is_meta = class_isMetaClass(object_getClass(obj))

                if is_meta {
                    // var meta_class = object_getClass(self.my_class)
                    // let addr = address(self.my_class)
                    return ClassForwarder(type(of: self).L, class: self.my_class)
                } else {
                    let ivar = class_getInstanceVariable(self.my_class, "__target")
                    let target = object_getIvar(obj, ivar!)
                    // let target = objc_getAssociatedObject(obj, "__target")

                    return target as! NSObject
                }
            }
            let sel = #selector(NSObject.forwardingTarget)
            let block: AnyObject = unsafeBitCast(forwarder, to: AnyObject.self)
            let imp = imp_implementationWithBlock(block)

            let method = class_getInstanceMethod(NSObject.self, sel)
            let encoding = method_getTypeEncoding(method!)
            class_addMethod(my_class, sel, imp, encoding)

            if let meta_class = object_getClass(my_class) {
                class_addMethod(meta_class, sel, imp, encoding)
            }
        }

        do {// responds(to:)
            let L = LuaClass.L!
            let responds: @convention(block) (AnyObject, Selector) -> Bool = { obj, sel in

                let class_name = object_getClassName(obj)
                lua_getglobal(L, class_name)
                assert(lua_type(L, -1) == LUA_TTABLE); // class

                let method_name = NSStringFromSelector(sel)

                // convert to lua function name
                let lua_method_name = method_name.replacingOccurrences(of: ":", with: "_")
                lua_getfield(L, -1, lua_method_name) // class, method
                let rslt = (lua_type(L, -1) == LUA_TFUNCTION)
                lua_pop(L, 2)

                print("response to: \(NSStringFromSelector(sel)) -> \(rslt))")

                return rslt
            }
            let sel = #selector(NSObject.responds(to:))
            let block: AnyObject = unsafeBitCast(responds, to: AnyObject.self)


            let imp = imp_implementationWithBlock(block)
            let method = class_getInstanceMethod(NSObject.self, sel)
            let encoding = method_getTypeEncoding(method!)
            class_addMethod(my_class, sel, imp, encoding)
        }

        // dealloc
        #if DEBUG
            do {
                let dealloc: @convention(block) (AnyObject) -> () = { obj in
                    var o = obj
                    print("deallocating: \(obj) \(hex(obj)) \(address(of: &o)))")
                    
                    // clear __swift_obj
                    lua_getglobal(L, "__swift_reg")
                    lua_pushlightuserdata(L, address(of: &o))
                    lua_gettable(L, -2) // __swift_reg, obj table
                    lua_pushnil(L) // __swift_reg, obj table, nil
                    lua_setfield(L, -2, "__swift_obj")
                    lua_pop(L, 2)
                    
                    lua_getglobal(L, "__cross_reg")
                    print_stack(L, "get __cross_reg")
                    
                    // remove from strong map
                    lua_pushlightuserdata(L, address(of: &o))
                    lua_pushnil(L)
                    lua_settable(L, -3) // __cross_reg[&obj] = nil
                    
                    lua_pop(L, 1)
                }

                let block: AnyObject = unsafeBitCast(dealloc, to: AnyObject.self)
                let imp = imp_implementationWithBlock(block)

                let sel = NSSelectorFromString("dealloc") // #selector(NSObject.deinit) //NSSelectorFromString("dealloc")
                let method = class_getInstanceMethod(NSObject.self, sel)
                let encoding = method_getTypeEncoding(method!)
                class_addMethod(my_class, sel, imp, encoding)
            }
        #endif

        objc_registerClassPair(my_class)

        // register class into lua
        create_meta(L, name, NSObject.self) // meta
        createCtor() // meta.__ctor set

        // __class = my_class
        let type_ptr: UnsafeMutableRawPointer = casting(&my_class)
        print("my class \(String(describing: my_class)), \(type_ptr)")
        lua_pushstring(L, "__class")
        lua_pushlightuserdata(L, type_ptr)
        lua_rawset(L, -3) // meta.__class = my_class

        lua_pop(L, 1)

        // var my_type = my_class
        LuaClass.meta_map.regNSRefPusher(type_ptr)
    }

    public func addProtoclMethod() {

    }

    private func createCtor() {
        let ctor = as_cfunc { [unowned self] L in
            let _ = self.newInstance(L)
            return 1
        }
        lua_pushcclosure(LuaClass.L, ctor, 0)
        lua_setfield(LuaClass.L, -2, "__ctor")
    }

    private func newInstance(_ L: L_STATE) -> AnyObject {
        var obj = my_class.alloc() as! NSObject
        // var obj = NSObject()
        object_setClass(obj, my_class)
        
        init_super(obj)

        var _ = type(of: obj)

        print("new instance: \(obj)")
        let ivar = class_getInstanceVariable(my_class, "__target")

        let target = ObjectForwarder(obj, l: LuaClass.L)
        object_setIvar(obj, ivar!, target)

        // like retain
        objc_setAssociatedObject(obj, "a__target", target, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)

        let addr = create_luaobj(LuaClass.L, &obj, type_name)
        
        // hold a strong reference, expecting release on the app side
        lua_getglobal(L, "__cross_reg")
        lua_pushlightuserdata(L, addr) // obj, __cross_reg, addr
        lua_pushvalue(L, -3) // obj, __cross_reg, addr, obj
        lua_rawset(L, -3) // obj, __cross_reg
        lua_pop(L, 1)

        print("before return: \(obj), \(hex(obj))")

        return obj
    }
}
