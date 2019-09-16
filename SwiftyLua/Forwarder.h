//
//  Forwarder.h
//  SwiftyLua
//
//  Created by hanzhao on 2017/3/9.
//  Copyright © 2017年 hanzhao. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <LuaSource/LuaSource.h>
#import <objc/message.h>
#import <objc/runtime.h>

@interface Forwarder : NSObject

@property (nonatomic, assign) lua_State * L;

- (instancetype) init: (lua_State *) L;
- (void) callLuaFunction: (NSInvocation *) invoke;

@end

void init_super(NSObject * obj);
void add_alloc_zone(Class meta_class);
void after(NSObject * obj);
int call_objc(lua_State * L, Method method, Class cls);
int call_objc_class(lua_State * L, Method method, Class cls);
void set_ivar(lua_State * L, Class cls, NSString * name);
void wax_printStack(lua_State *L, NSString * msg);
void wax_luaLock(lua_State * L);
void wax_luaUnlock(lua_State * L);
void compare_L(lua_State * lhs, lua_State * rhs);
void add_call(Class cls, SEL sel);
void reg_L(lua_State * L, NSThread * thread);
void patch_sel(Class cls, SEL sel, IMP imp);
void DLog(NSInteger level, NSString * format, ...);
// int traceback (lua_State *L);
int error_handler(lua_State * L);

#define SLog(format, ...)\
    DLog(s_level, format, ##__VA_ARGS__)

void swizzleInstanceMethods(Class klass, SEL original, SEL new);
