//
//  Trait.swift
//  SwiftyLua
//
//  Created by hanzhao on 2017/8/3.
//  Copyright © 2017年 hanzhao. All rights reserved.
//

import Foundation

private let print = Logger.genPrint(level: .trait)

public struct FuncTrait {

    public init() {}

    public func prop<T, R>(_ kp: KeyPath<T, R>) -> (T) -> R {
        return { t in
            return t[keyPath: kp]
        }
    }
    
    public struct MulProp<T, R> {
        var getter: (T) -> R
        var setter: (T, R) -> ()
    }
    
    public func props<T, R>(_ kp: ReferenceWritableKeyPath<T, R>) -> MulProp<T, R> {
        let getter: (T) -> R = { t in
            return t[keyPath: kp]
        }
        let setter: (T, R) -> () = { t, r in
            t[keyPath: kp] = r
        }
        return MulProp(getter: getter, setter: setter)
    }

    // MARK: methods
    public func instance<OBJ, R>(_ method: @escaping (OBJ) -> () -> (R)) -> (L_STATE, OBJ, ArgLoader) -> R {
        return { L, obj, arg_loader in
            let call = method(obj)
            return call()
        }
    }


    public func instance<OBJ, A, R>(_ method: @escaping (inout OBJ)-> (A) -> (R)) -> (L_STATE, OBJ, ArgLoader) -> R {
        return { L, obj, arg_loader in
            print("value type : \(OBJ.self) -> \(A.self) -> \(R.self))")
            let a: A = arg_loader.load(L)

            // inout
            var o = obj
            let call = method(&o)

            return call(a)
        }
    }

    public func instance<OBJ, A, R>(_ method: @escaping (OBJ)-> (A) -> (R)) -> (L_STATE, OBJ, ArgLoader) -> R {
        return { L, obj, arg_loader in
            print("reference type : \(OBJ.self) -> \(A.self) -> \(R.self)")
            let a: A = arg_loader.load(L)

            let call = method(obj)
            return call(a)
        }
    }


    public func instance<OBJ, A1, A2, R>(_ method: @escaping (OBJ)-> (A1, A2) -> (R)) -> (L_STATE, OBJ, ArgLoader) -> R {
        return { L, obj, arg_loader in
            let a2: A2 = arg_loader.load(L)
            let a1: A1 = arg_loader.load(L)

            let call = method(obj)
            return call(a1, a2)
        }
    }

    public func instance<OBJ, A1, A2, A3, R>(_ method: @escaping (OBJ)-> (A1, A2, A3) -> (R)) -> (L_STATE, OBJ, ArgLoader) -> R {
        return { L, obj, arg_loader in
            let a3: A3 = arg_loader.load(L)
            let a2: A2 = arg_loader.load(L)
            let a1: A1 = arg_loader.load(L)

            let call = method(obj)
            return call(a1, a2, a3)
        }
    }

    public func instance<OBJ, A1, A2, A3, A4, R>(_ method: @escaping (OBJ)-> (A1, A2, A3, A4) -> (R)) -> (L_STATE, OBJ, ArgLoader) -> R {
        return { L, obj, arg_loader in
            let a4: A4 = arg_loader.load(L)
            let a3: A3 = arg_loader.load(L)
            let a2: A2 = arg_loader.load(L)
            let a1: A1 = arg_loader.load(L)

            let call = method(obj)
            return call(a1, a2, a3, a4)
        }
    }

    public func instance<OBJ, A1, A2, A3, A4, A5, R>(_ method: @escaping (OBJ)-> (A1, A2, A3, A4, A5) -> (R)) -> (L_STATE, OBJ, ArgLoader) -> R {
        return { L, obj, arg_loader in

            let a5: A5 = arg_loader.load(L)
            let a4: A4 = arg_loader.load(L)
            let a3: A3 = arg_loader.load(L)
            let a2: A2 = arg_loader.load(L)
            let a1: A1 = arg_loader.load(L)

            let call = method(obj)
            return call(a1, a2, a3, a4, a5)
        }
    }

    public func instance<OBJ, A1, A2, A3, A4, A5, A6, R>(_ method: @escaping (OBJ)-> (A1, A2, A3, A4, A5, A6) -> (R)) -> (L_STATE, OBJ, ArgLoader) -> R {
        return { L, obj, arg_loader in

            let a6: A6 = arg_loader.load(L)
            let a5: A5 = arg_loader.load(L)
            let a4: A4 = arg_loader.load(L)
            let a3: A3 = arg_loader.load(L)
            let a2: A2 = arg_loader.load(L)
            let a1: A1 = arg_loader.load(L)

            let call = method(obj)
            return call(a1, a2, a3, a4, a5, a6)
        }
    }

    // MARK: - static methods
    public func `static`<R>(_ method: @escaping (()) -> (R)) -> (L_STATE, ArgLoader) -> (R) {
        return { L, arg_loader  in
            // return ()
            return method(())
        }
    }

    public func `static`<A1, R>(_ method: @escaping ((A1)) -> (R)) -> (L_STATE, ArgLoader) -> (R) {
        return { L, arg_loader in
            let a1: A1 = arg_loader.load(L)

            return method(a1)
        }
    }

    // arg loader may load arg in a different thread than the defining L
    public func `static`<A1, A2, R>(_ method: @escaping ((A1, A2)) -> (R)) -> (L_STATE, ArgLoader) -> (R) {
        return { L, arg_loader in
            let a2: A2 = arg_loader.load(L)
            let a1: A1 = arg_loader.load(L)

            return method((a1, a2))
        }
    }

    public func `static`<A1, A2, A3, R>(_ method: @escaping ((A1, A2, A3)) -> (R)) -> (L_STATE, ArgLoader) -> (R) {
        return { L, arg_loader in
            let a3: A3 = arg_loader.load(L)
            let a2: A2 = arg_loader.load(L)
            let a1: A1 = arg_loader.load(L)
            
            return method((a1, a2, a3))
        }
    }

    public func `static`<A1, A2, A3, A4, R>(_ method: @escaping ((A1, A2, A3, A4)) -> (R)) -> (L_STATE, ArgLoader) -> (R) {
        return { L, arg_loader in
            let a4: A4 = arg_loader.load(L)
            let a3: A3 = arg_loader.load(L)
            let a2: A2 = arg_loader.load(L)
            let a1: A1 = arg_loader.load(L)

            return method((a1, a2, a3, a4))
        }
    }

    public func `static`<A1, A2, A3, A4, A5, R>(_ method: @escaping ((A1, A2, A3, A4, A5)) -> (R)) -> (L_STATE, ArgLoader) -> (R) {
        return { L, arg_loader in
            let a5: A5 = arg_loader.load(L)
            let a4: A4 = arg_loader.load(L)
            let a3: A3 = arg_loader.load(L)
            let a2: A2 = arg_loader.load(L)
            let a1: A1 = arg_loader.load(L)

            return method((a1, a2, a3, a4, a5))
        }
    }

    public func `static`<A1, A2, A3, A4, A5, A6, R>(_ method: @escaping ((A1, A2, A3, A4, A5, A6)) -> (R)) -> (L_STATE, ArgLoader) -> (R) {
        return { L, arg_loader in
            let a6: A6 = arg_loader.load(L)
            let a5: A5 = arg_loader.load(L)
            let a4: A4 = arg_loader.load(L)
            let a3: A3 = arg_loader.load(L)
            let a2: A2 = arg_loader.load(L)
            let a1: A1 = arg_loader.load(L)

            return method((a1, a2, a3, a4, a5, a6))
        }
    }
}
