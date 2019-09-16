//
//  ClassForwarder.m
//  SwiftyLua
//
//  Created by hanzhao on 2017/3/3.
//  Copyright © 2017年 hanzhao. All rights reserved.
//

#import "ClassForwarder.h"
#import <objc/runtime.h>
#import <LuaSource/LuaSource.h>

void l_printStackAt(lua_State *L, int i) {
    int t = lua_type(L, i);
    printf("(%s) ", lua_typename(L, t));

    switch (t) {
        case LUA_TSTRING:
            printf("'%s'", lua_tostring(L, i));
            break;
        case LUA_TBOOLEAN:
            printf(lua_toboolean(L, i) ? "true" : "false");
            break;
        case LUA_TNUMBER:
            printf("'%g'", lua_tonumber(L, i));
            break;
        case LUA_TTABLE:
            printf("%p\n{\n", lua_topointer(L, i));
            //            wax_printTable(L, i);
            printf("}");
            break;
        default:
            printf("%p", lua_topointer(L, i));
            break;
    }
}

void l_printTable(lua_State *L, int t) {
    // table is in the stack at index 't'

    if (t < 0) t = lua_gettop(L) + t + 1; // if t is negative, we need to normalize
    if (t <= 0 || t > lua_gettop(L)) {
        printf("%d is not within stack boundries.\n", t);
        return;
    }
    else if (!lua_istable(L, t)) {
        printf("Object at stack index %d is not a table.\n", t);
        return;
    }

    lua_pushnil(L);  // first key
    while (lua_next(L, t) != 0) {
        l_printStackAt(L, -2);
        printf(" : ");
        l_printStackAt(L, -1);
        printf("\n");

        lua_pop(L, 1); // remove 'value'; keeps 'key' for next iteration
    }
}

void l_printStack(lua_State *L) {
    int i;
    int top = lua_gettop(L);

    for (i = 1; i <= top; i++) {
        printf("%d: ", i);
        l_printStackAt(L, i);
        printf("\n");
    }

    printf("\n");
}

@interface ClassForwarder()

@property (nonatomic, retain) Class cls;

@end

@implementation ClassForwarder

- (instancetype) init: (lua_State *) L class: (Class) cls_addr {
    if (self = [super init: L]) {
        self.cls = cls_addr;
    }
    return self;
}

- (NSMethodSignature *) methodSignatureForSelector:(SEL)aSelector {
    NSMethodSignature * sig = [self.cls instanceMethodSignatureForSelector: aSelector];
    if (sig == nil) {
        // check in protocols
        unsigned int n = 0;
        __unsafe_unretained Protocol ** protos = class_copyProtocolList(self.cls, &n);
        for (int i = 0; i < n; ++i) {
            Protocol * proto = protos[i];
            NSLog(@"%d) %s", i, protocol_getName(proto));

            unsigned int method_n = 0;
            struct objc_method_description * descs = protocol_copyMethodDescriptionList(proto, true, false, &method_n);
            for (int j = 0; j < method_n; ++j) {
                struct objc_method_description desc = descs[j];
                if (desc.name == aSelector) {
                    sig = [NSMethodSignature signatureWithObjCTypes: desc.types];
                    break;
                }
            }

            free(descs);
        }

        free(protos);
    }
    assert(sig != nil);
    return sig;
}

- (void) forwardInvocation:(NSInvocation *) invoke {
    NSLog(@"forwarding class method: %@ %@", invoke, NSStringFromSelector(invoke.selector));

    // lua_pushcfunction(self.L, error_handler);

    const char * class_name = class_getName(self.cls);
    lua_getglobal(self.L, class_name);
    assert(lua_type(self.L, -1) == LUA_TTABLE); // class

    NSString * method_name = NSStringFromSelector(invoke.selector);
    NSString * sanity_name = [method_name stringByReplacingOccurrencesOfString: @":" withString: @"_"];
    lua_getfield(self.L, -1, sanity_name.UTF8String); // class, func
    if (lua_type(self.L, -1) != LUA_TFUNCTION) {
        NSLog(@"expecting function %@, but get: %d", method_name, lua_type(self.L, -1));
        assert(false);
    }

    lua_pushvalue(self.L, -2); // class, func, class
    lua_remove(self.L, -3); // func, class

    [self callLuaFunction: invoke];
}

@end
