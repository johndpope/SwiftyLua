//
//  BridgeTests.swift
//  BridgeTests
//
//  Created by hanzhao on 2017/2/6.
//  Copyright © 2017年 hanzhao. All rights reserved.
//

import XCTest
import SwiftyLua
import ObjectiveC.runtime

class Bar {
    let message = "bar is class"

    /*init(_: Void) {
    }*/
}

struct SBar {
    var message = "sbar is struct"

    init(_ str: String) {
        print("sbar ctoring: \(self) -> \(str)")
        self.message = str
    }

    func msg() -> String {
        print("get message: \(self.message)")
        return self.message
    }

    mutating func change(_ msg: String) {
        print("changing to: \(msg) \(hexString(bytes: bytes(of: self))))")
        self.message = msg
        print("after: \(msg) \(hexString(bytes: bytes(of: self))))")
    }
}

class Foo {
    let message = "hello from swift"
    var hp: Int?
    var bar: Bar?
    var sbar: SBar = SBar("in swift")
    var sbar_opt: SBar?

    init(_: Void) {
        print("Foo ctor, self: \(self)")
    }

    init(hp: Int) {
        print("hp is: \(hp), self: \(self) \(self.message)")
        self.hp = hp
    }

    init(hp: Int, ap: Int) {
        print("hp \(hp), ap \(ap)")
    }

    deinit {
        print("dtor: \(self)")
    }

    func getHp() -> Int {
        return hp ?? 0
    }

    func talk(n: Int, more: String) {
        print("saying: \(n) \(more)")
    }

    func talkWith(bar: Bar?) {
        print("talk with bar: \(String(describing: bar))")
        self.bar = bar
    }

    func talkWithS(bar: SBar) {
        print("talk with sbar: \(bar)")
    }

    func talkWithSOpt(bar: SBar?) {
        print("talk with sbar opt: \(String(describing: bar))")
        self.sbar_opt = bar
    }

    func theBar() -> Bar? {
        let bar_any = self.bar as Any?
        print("\(String(describing: bar_any)), \(type(of: bar_any)), \(bar_any!), \(type(of: bar_any!))")
        return self.bar
    }

    func simple(n: Int, x: Int) {
        print("simple: \(n), \(x)")
    }

    func desc() {
        print("foo: \(String(describing: hp)) \(message)")
    }

    func theSBar() -> SBar {
        return self.sbar
    }

    func theSBarOpt() -> SBar? {
        return self.sbar_opt
    }

    func iarr() -> [Int] {
        return [1, 2]
    }
}

protocol A {}
protocol B {}

struct Car: A, B {
    let msg = "I'm a car"
}

class BridgeTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // uncap(bar)
        // container(bar_opt)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testForward() {
        
    }

    func doReferenceCount() {
        let ptr = UnsafeMutablePointer<Foo>.allocate(capacity: 1)
        ptr.initialize(to: Foo())
        ptr.deinitialize()
    }

    func testMetaMap() {
        var v = Int.self
        withUnsafeBytes(of: &v) { ptr in
            print("ptr for \(v) is \(ptr)")
        }
        print("for int", hex(Int.self, reverse: true))
        var s = String.self
        withUnsafeBytes(of: &s) { ptr in
            print("ptr for \(v) is \(ptr)")
        }
        print("for string", hex(String.self, reverse: true))

        // let i_opt: Int? = 1
    }

    func testAny() {
        assert(sizeof(Any.self) == sizeof(InfAny.self))

        let car_opt: Car? = Car()
        let car_opt_any_opt = car_opt as Any?
        assert(car_opt_any_opt != nil)

        let bar = Bar()
        let bar_opt: Bar? = bar
        let bar_any = bar as Any
        print(hex(bar_any))
        let bar_opt_any = bar_opt as Any
        print(hex(bar_opt_any))
        let bar_opt_any_opt = bar_opt as Any?
        print(hex(bar_opt_any_opt))

        var type = Bar.self
        withUnsafePointer(to: &type) { ptr in
            print("\(hex(ptr))")
        }

        let bar_opt_opt: Bar?? = bar
        // MARK: reopen
        // let bar_opt_opt_any_opt = bar_opt_opt as Any?
        // print(hex(bar_opt_opt_any_opt))
        let bar_opt_opt_any_opt_opt = bar_opt_opt as Any??
        print(hex(bar_opt_opt_any_opt_opt))

        let bar_nil_opt: Bar? = nil
        let bar_nil_opt_any = bar_nil_opt as Any?
        print(hex(bar_nil_opt_any))

        let i: Int? = 1
        let i_any_opt = i as Any?
        print(hex(i), hex(i_any_opt))

        let ii: Int??? = 1
        print(hex(ii))
        // MARK: reopen
        // let ii_any_opt = ii as Any?
        // print(hex(ii_any_opt))

        let i_s: Int = 1
        print(hex(i_s))
        
        let i_s_any = i_s as Any
        print(hex(i_s_any))
    }
    
    func testBridgeInit() {
        let bridge = LuaBridge { L, meta_map in
            print("reg: \(Foo.self)")

            do {
                meta_map.regPusher(Int.self)
                meta_map.regPusher(String.self)
                meta_map.regPusher(Bar.self)
                meta_map.regPusher(SBar.self)

                meta_map.regLoader(Int.self)
                meta_map.regLoader(String.self)
                meta_map.regLoader([String].self)
            }

            do {
                let reg = TypeReg<Foo>(L, meta_map)

                reg.ctor(wrapper(Foo.init(_:)), "init", reg.trait.ctor(Foo.init(_:)))
                reg.ctor(wrapper(Foo.init(hp:)), "init_hp", reg.trait.ctor(Foo.init(hp:)))


                reg.method(Foo.talk, "talk", reg.trait.method(Foo.talk))
                reg.method(Foo.desc, "desc", reg.trait.method(Foo.desc))
                reg.method(Foo.getHp, "hp", reg.trait.method(Foo.getHp))
                reg.method(Foo.talkWith, "talk_with", reg.trait.method(Foo.talkWith))
                reg.method(Foo.talkWithS, "talk_with_s", reg.trait.method(Foo.talkWithS))
                reg.method(Foo.talkWithSOpt, "talk_with_sbar_opt", reg.trait.method(Foo.talkWithSOpt))
                reg.method(Foo.theBar, "the_bar_opt", reg.trait.method(Foo.theBar))
                reg.method(Foo.theSBar, "the_sbar", reg.trait.method(Foo.theSBar))
                reg.method(Foo.theSBarOpt, "the_sbar_opt", reg.trait.method(Foo.theSBarOpt))
                reg.method(Foo.iarr, "iarr", reg.trait.method(Foo.iarr))
            }

            do {
                print("reg: \(Bar.self)")
                let reg = TypeReg<Bar>(L, meta_map)
                reg.ctor(wrapper(Bar.init), "init", reg.trait.ctor(Bar.init))
            }

            do {
                let reg = TypeReg<SBar>(L, meta_map)
                reg.ctor(wrapper(SBar.init), "init", reg.trait.ctor(SBar.init))
                reg.method(SBar.change(_:), "change", reg.trait.method(SBar.change(_:)))
                reg.method(SBar.msg, "message", reg.trait.method(SBar.msg))
            }
        }
        print("lua stat: \(bridge.L)")
        bridge.eval("print('hello from bridge')")

        print("bundle path: \(Bundle.main.bundlePath)")

        if let cls = NSClassFromString("MyClass") {
        let pro = cls as AnyObject as! HelloProtocol.Type
        let obj = pro.create()
        print("obj from lua: \(String(describing: obj))")
        obj?.hello()
        }
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
}
