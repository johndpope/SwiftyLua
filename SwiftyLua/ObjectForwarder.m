//
//  SwiftObj.m
//  SwiftyLua
//
//  Created by hanzhao on 2017/2/26.
//  Copyright © 2017年 hanzhao. All rights reserved.
//

#import "ObjectForwarder.h"
#import "ClassForwarder.h"
#import <SwiftyLua/SwiftyLua-Swift.h>

static LogLevel s_level = LogLevelObjc;

@interface ObjectForwarder ()

@property (nonatomic, assign) id host;

@end

@implementation ObjectForwarder

- (instancetype) init: (id) host L: (lua_State *) L {
    if (self = [super init: L]) {
        self.host = host;
    }
    return self;
}

- (void) dealloc {
    SLog(@"dealloc swift obj: %@", self.host);
    self.host = nil;
}

- (NSMethodSignature *) methodSignatureForSelector:(SEL)aSelector {
    SLog(@"signature for: %@", NSStringFromSelector(aSelector));
    /*if (aSelector == @selector(collectionView:layout:sizeForItemAtIndexPath:)) {
        SLog(@"catched");
    }*/
    NSMethodSignature * sig = [self.host methodSignatureForSelector: aSelector];
    assert(sig != nil);
    return sig;
}

- (void) forwardInvocation:(NSInvocation *) invoke {
    lua_State * t_L = [[NSThread currentThread] L];
    assert(t_L != nil);
    if (t_L != self.L) {
        SLog(@"forwarding, but L is different: cur thread L %p, self L: %p", t_L, self.L);
    }
    
    NSMethodSignature * sig = invoke.methodSignature;
    SLog(@"forwarding: %@: %s narg: %lu, return %s", invoke, sel_getName(invoke.selector), (unsigned long)sig.numberOfArguments, sig.methodReturnType);

    // push error handler
    // lua_pushcfunction(self.L, error_handler);

    const char * class_name = object_getClassName(self.host);
    lua_getglobal(t_L, class_name);
    assert(lua_type(t_L, -1) == LUA_TTABLE); // error_handler, class

    NSString * method_name = NSStringFromSelector(invoke.selector);

    // convert to lua function name
    NSString * lua_method_name = [method_name stringByReplacingOccurrencesOfString: @":" withString: @"_"];
    lua_getfield(t_L, -1, lua_method_name.UTF8String); // error_handler, class, func
    if (lua_isnil(t_L, -1)) { // error_handler, class, nil
        lua_pop(t_L, 1); // error_handler, class

        // if lua method name has no the last _, take it as sanity too
        if ([lua_method_name characterAtIndex: lua_method_name.length - 1] == '_') {
            lua_method_name = [lua_method_name substringToIndex: lua_method_name.length - 1];
            lua_getfield(t_L, -1, lua_method_name.UTF8String);
        }
    }
    assert(lua_type(t_L, -1) == LUA_TFUNCTION);
    lua_remove(t_L, -2); // error_handler, func

    // find the lua obj
    lua_getglobal(t_L, "__swift_reg"); // error_handler, func, reg
    assert(lua_type(t_L, -1) == LUA_TTABLE);
    lua_pushlightuserdata(t_L, (__bridge void *) self.host); // error_handler, func, reg, host
    lua_gettable(t_L, -2); // error_handler, func, reg, lua_obj
    if (lua_type(t_L, -1) != LUA_TTABLE) {
        wax_printStack(t_L, @"error in forward invoke");
    }
    assert(lua_type(t_L, -1) == LUA_TTABLE);

    lua_remove(t_L, -2); // error_handler, func, lua_obj

    [self callLuaFunction: invoke];
}

@end
