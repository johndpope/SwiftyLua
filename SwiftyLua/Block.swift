//
//  Block.swift
//  SwiftyLua
//
//  Created by Zhao Han on 11/8/18.
//  Copyright © 2018 hanzhao. All rights reserved.
//

import Foundation

public class BlockCallContext {
    private let bridge: LuaBridge = LuaBridge(fromThread: Thread.current.bridge!)
    let thread = Thread.current.id
    
    private let captures: [AnyObject]?
    private let blockKey: String
    
    init(_ L: L_STATE, _ key: String) {
        self.blockKey = __.reg_block(L, key)
        
        self.captures = __.captured(L, at: -1)
        __.retain(captures)
    }
    
    deinit {
        __.release(captures)
    }
    
    public func call_block<R>(_ arg_pusher: (L_STATE) -> Int, _ arg_loader: ArgLoader) -> R {
        __.forkWith(bridge)
        return __.do_call_block(bridge.L, blockKey, arg_pusher, arg_loader)
    }
    
    // yes, __ as struct name
    private struct __ {
        static func captured(_ L: L_STATE, at f_idx: Int) -> [AnyObject]? {
            var objs: [AnyObject]? = nil
            inspectUpvalues(L, at: f_idx) { val_idx in
                if lua_type(L, val_idx) == LUA_TTABLE {
                    lua_pushstring(L, "__swift_type")
                    lua_rawget(L, -2)
                    
                    if lua_isstring(L, -1) {
                        let swift_type = lua_tostring(L, -1)
                        lua_pop(L, 1)
                        print("captured type: ", swift_type)
                        if swift_type != "struct" {
                            lua_pushstring(L, "__swift_obj")
                            lua_rawget(L, -2)
                            
                            if lua_isuserdata(L, -1) == 1 {
                                if objs == nil {
                                    objs = [AnyObject]()
                                }
                                
                                let ptr = lua_touserdata(L, -1)!
                                
                                switch lua_type(L, -1) {
                                case LUA_TLIGHTUSERDATA:
                                    objs!.append(dereference(ptr))
                                    
                                case LUA_TUSERDATA:
                                    let binded = ptr.bindMemory(to: AnyObject.self, capacity: 1)
                                    objs!.append(binded.pointee)
                                    
                                default:
                                    assert(false)
                                }
                            }
                            
                            lua_pop(L, 1)
                        }
                    } else {
                        lua_pop(L, 1) // nil or whatever
                    }
                }
            }
            return objs
        }
        
        static func inspectUpvalues(_ L: L_STATE, at f_idx: Int, _ inspector: (_ val_idx: Int) -> ()) {
            // inspect the upvalues
            var up_idx: Int32 = 1
            while true {
                if let nm = lua_getupvalue(L, Int32(f_idx), up_idx) {
                    let c_nm = nm as UnsafePointer<CChar>
                    let name = String(cString: c_nm)
                    print("up \(up_idx): \(name) \(lua_type(L, -1))")
                    
                    inspector(-1)
                    
                    lua_pop(L, 1)
                    up_idx += 1
                } else {
                    break
                }
            }
        }
        
        static func retain(_ captures: [AnyObject]?) {
            captures?.forEach {let _ = Unmanaged.passUnretained($0).retain()}
        }
        
        static func release(_ captures: [AnyObject]?) {
            captures?.forEach {let _ = Unmanaged.passUnretained($0).release()}
        }
        
        // lua func on top
        static func reg_block(_ L: L_STATE, _ key: String) -> String {
            assert(lua_isfunction(L, -1))
            
            // get the block ptr
            let block_ptr = lua_topointer(L, -1)
            
            let block_key = "lua-block-key, signature: \(key) -> \(block_ptr!)"
            lua_getglobal(L, "__block_reg") // reg
            
            t_print("reg block with key: \(block_key)")
            // is there a conflict?
            lua_getfield(L, -1, block_key)
            if (lua_isnil(L, -1)) {
                lua_pop(L, 1)
                
                lua_pushvalue(L, -2) // reg, func
                lua_setfield(L, -2, block_key)
            } else {
                t_print("already registerd; may be a conflict - but let's go withit now")
                lua_pop(L, 1) // pop off the block
            }
            
            // pop off reg
            lua_pop(L, 1)
            
            return block_key
        }
        
        static func forkWith(_ bridge: LuaBridge) {
            let cur_thread = Thread.current
            
            if cur_thread.bridge == nil {
                cur_thread.regBridge(bridge)
            } else {
                
            }
        }
        
        static func do_call_block<R>(_ L: L_STATE, _ key: String, _ arg_pusher: (L_STATE) -> Int, _ arg_loader: ArgLoader) -> R {
            t_print("--> do call block on \(L), key: \(key)")
            
            // var debug = lua_Debug()
            // let rslt = lua_getstack(L, 0, &debug)
            
            // shared states
            lua_getglobal(L, "__block_reg") // reg
            lua_getfield(L, -1, key) // reg, func
            
            // print_stack(L, "get func on thread: \(Thread.current)")
            assert(lua_isfunction(L, -1))
            lua_remove(L, -2) // func
            
            /*if let captured = capturedObjects(L, at: -1) {
             print("total captured: \(captured)")
             }*/
            
            let eh_pos = Int(lua_gettop(L))
            lua_pushcfunction(L, error_handler); // func, eh
            // print_stack(L, "before insert error handler")
            lua_insert(L, eh_pos) // eh, func
            // print_stack(L, "after insert error handler")
            
            // push to lua
            let n_arg = arg_pusher(L)
            
            // print_stack(L, "pre call \(Thread.current)")
            // call lua
            let n_ret = R.self == Void.self ? 0 : 1
            
            var call_rslt = Int(LUA_OK)
            call_rslt = lua_pcall(L, n_arg, n_ret, eh_pos)
            
            // print_stack(L, "will remove error handler")
            // remove error handler
            lua_remove(L, eh_pos);
            
            if (call_rslt != Int(LUA_OK)) {
                print_stack(L, .bridge, "failed to call block \(Thread.current), ret: \(call_rslt)")
                let err = lua_tostring(L, -1)
                print("call lua callback failed: \(err)")
                assert(false)
            }
            
            t_print("<-- end call block on \(L), key: \(key)")
            // load ret
            if n_ret == 0 {
                return () as! R
            } else {
                // let arg_loader = ArgLoader(self.meta_map, self.block_map)
                let ret: R = arg_loader.load(L)
                return ret
            }
        }
    }
}
