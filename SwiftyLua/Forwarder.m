//
//  Forwarder.m
//  SwiftyLua
//
//  Created by hanzhao on 2017/3/9.
//  Copyright © 2017年 hanzhao. All rights reserved.
//

#import "Forwarder.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <UIKit/UIKit.h>
#import "wax.h"
#import <SwiftyLua/SwiftyLua-Swift.h>
#import "macros.h"

void swizzleInstanceMethods(Class klass, SEL original, SEL new) {
    Method origMethod = class_getInstanceMethod(klass, original);
    Method newMethod = class_getInstanceMethod(klass, new);
    
    if (class_addMethod(klass, original, method_getImplementation(newMethod), method_getTypeEncoding(newMethod))) {
        class_replaceMethod(klass, new, method_getImplementation(origMethod), method_getTypeEncoding(origMethod));
    } else {
        method_exchangeImplementations(origMethod, newMethod);
    }
}

// @ref: https://stackoverflow.com/questions/8461902/how-to-resolve-property-getter-setter-method-selector-using-runtime-reflection-i
@interface NSObject (Ext)

+(SEL)getterForPropertyWithName:(NSString*)name;
+(SEL)setterForPropertyWithName:(NSString*)name;

@end

@implementation NSObject (Ext)

+(SEL)getterForPropertyWithName:(NSString*)name {
    const char* propertyName = [name cStringUsingEncoding:NSASCIIStringEncoding];
    objc_property_t prop = class_getProperty(self, propertyName);

    const char *selectorName = property_copyAttributeValue(prop, "G");
    if (selectorName == NULL) {
        selectorName = [name cStringUsingEncoding:NSASCIIStringEncoding];
    }
    NSString* selectorString = [NSString stringWithCString:selectorName encoding:NSASCIIStringEncoding];
    return NSSelectorFromString(selectorString);
}

+(SEL)setterForPropertyWithName:(NSString*)name {
    const char* propertyName = [name cStringUsingEncoding:NSASCIIStringEncoding];
    objc_property_t prop = class_getProperty(self, propertyName);

    char *selectorName = property_copyAttributeValue(prop, "S");
    NSString* selectorString;
    if (selectorName == NULL) {
        char firstChar = (char)toupper(propertyName[0]);
        NSString* capitalLetter = [NSString stringWithFormat:@"%c", firstChar];
        NSString* reminder      = [NSString stringWithCString: propertyName+1
                                                     encoding: NSASCIIStringEncoding];
        selectorString = [@[@"set", capitalLetter, reminder, @":"] componentsJoinedByString:@""];
    } else {
        selectorString = [NSString stringWithCString:selectorName encoding:NSASCIIStringEncoding];
    }

    return NSSelectorFromString(selectorString);
}

@end

static LogLevel s_level = LogLevelObjc;

void DLog(NSInteger level, NSString * format, ...) {
    if ([Logger level] & level) {
        va_list ap;
        va_start(ap, format);
        NSLogv(format, ap);
        va_end(ap);
    }
}

static void wax_printStackAt(lua_State *L, int i);

void wax_luaLock(lua_State * L) {
    lua_lock(L);
}

void wax_luaUnlock(lua_State * L) {
    lua_unlock(L);
}

void wax_printTable(lua_State *L, int t) {
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
        wax_printStackAt(L, -2);
        printf(" : ");
        wax_printStackAt(L, -1);
        printf("\n");

        lua_pop(L, 1); // remove 'value'; keeps 'key' for next iteration
    }
}

static void wax_printStackAt(lua_State *L, int i) {
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
                        // wax_printTable(L, i);
            printf("}");
            break;
        default:
            printf("%p", lua_topointer(L, i));
            break;
    }
}

void wax_printStack(lua_State *L, NSString * msg) {
    [SwiftyLua printStack: L message: msg];
    /*
    int i;
    int top = lua_gettop(L);

    for (i = 1; i <= top; i++) {
        printf("%d: ", i);
        wax_printStackAt(L, i);
        printf("\n");
    }

    printf("\n");*/
}

static int traceback (lua_State *L) {
    if (!lua_isstring(L, 1))  /* 'message' not a string? */
        return 1;  /* keep it intact */
    // lua_getfield(L, LUA_GLOBALSINDEX, "debug");
    lua_getglobal(L, "debug");
    if (!lua_istable(L, -1)) {
        lua_pop(L, 1);
        return 1;
    }
    lua_getfield(L, -1, "traceback");
    if (!lua_isfunction(L, -1)) {
        lua_pop(L, 2);
        return 1;
    }
    lua_pushvalue(L, 1);  /* pass error message */
    lua_pushinteger(L, 2);  /* skip this function and traceback */
    lua_call(L, 2, 1);  /* call debug.traceback */
    return 1;
}

/**
 * ref: http://stackoverflow.com/questions/12256455/print-stacktrace-from-c-code-with-embedded-lua
 * The stack has not been unwound when the error function is called, so you can get a stack trace there.
 */
int error_handler(lua_State * L) {
    wax_printStack(L, @"in error handler");
    traceback(L);
    const char * msg = lua_tostring(L, -1);
    SLog(@"in error handler --->:\n %s \n<---", msg);
    // lua_pop(L, 1); // pop off error msg

    return 1;
}

static int do_call(lua_State * L, id obj, Method method, NSMethodSignature * sig);

void objc_sendMessage(id obj, SEL mtd) {
    ((void (*)(id, SEL, ...))objc_msgSend)(obj, mtd);
}

int call_objc_class(lua_State * L, Method method, Class cls) {
    SEL sel = method_getName(method);
    SLog(@"call method on class: %s -> %@", class_getName(cls), NSStringFromSelector(sel));

    NSMethodSignature * sig = [cls methodSignatureForSelector: sel];
    assert(sig);

    return do_call(L, cls, method, sig);
}

NSMethodSignature * instanceMethodSignatureForSelector(Class cls, SEL sel) {
    return [cls instanceMethodSignatureForSelector: sel];
}

void reg_L(lua_State * L, NSThread * thread) {
    NSMutableDictionary * dict = thread.threadDictionary;
    dict[@"__bridge_L"] = [NSValue valueWithPointer: L];

    SLog(@"registering L %p on thread %@ (is main %d), current thread is %@", L, thread, thread.isMainThread, [NSThread currentThread]);
}

void patch_sel(Class cls, SEL sel, IMP imp) {
    Method mtd = class_getInstanceMethod(cls, sel);
    const char * encode = method_getTypeEncoding(mtd);
    class_addMethod(cls, sel, imp, encode);
}

/**
 * ARM v6 stack layout
 * https://developer.apple.com/library/content/documentation/Xcode/Conceptual/iPhoneOSABIReference/Articles/ARMv6FunctionCallingConventions.html
 *
 * arm64 va_arg:
 * https://forums.developer.apple.com/thread/38470
 * On 64-bit ARM varargs routines use different calling conventions from standard routines, thus implementing a non-varargs method with a varargs 
 * block is simply not feasible.
 * This limitation is not just for 64-bit ARM.  There are similar differences between varargs and non-varargs calling conventions on other runtime 
 * architectures as well, it’s just that those differences general occur at the ‘edges’ of the runtime architecture and thus you don’t trip over them
 * very often.
 */
void add_call(Class cls, SEL sel) {
#if 0
    NSMethodSignature * sig = [cls instanceMethodSignatureForSelector: sel];
    // NSInvocation * invoke = [NSInvocation invocationWithMethodSignature: sig];
     id blk = ^ (id obj, ...) {
         NSDictionary * dict = [[NSThread currentThread] threadDictionary];
         SLog(@"on thread: %@ %@, %p %p", [NSThread currentThread], dict, &dict, &obj);
         lua_State * L = [dict[@"__bridge_L"] pointerValue];

         wax_printStack(L, @"before calling added method");

         /*
         va_list ap;
         va_start(ap, obj);
         id arg = va_arg(ap, id);
         NSLog(@"arg: %@", arg);
         va_end(ap);*/


        /*void * frame = &obj;
        NSLog(@"in frame on: %@, stack frame %p %lu", NSStringFromSelector(sel), &obj, (unsigned long)sig.frameLength);
        assert(sig.numberOfArguments >= 2); // obj, cmd

        for (int i = 0; i < sig.numberOfArguments; ++i) {
            const char * type_desc = [sig getArgumentTypeAtIndex: i];

            if (type_desc[0] != ':') {
                int len = [Wax sizeOfDesc: type_desc];
                [Wax fromObjc: L type: type_desc buffer: frame];
                frame += len;

                //id arg = va_arg(args, NSObject*);
                //NSLog(@"ret: %@", arg);
            }
        }
        
        // call
        
        // ret*/
    };

    SLog(@"imp with block: %@ for %@", blk, NSStringFromSelector(sel));
    patch_sel(cls, sel, imp_implementationWithBlock(blk));
#endif
}

static id to_obj(lua_State * L, int index) {
    int idx = index > 0 ? index : index - 1;
    lua_pushstring(L, "__passing_style");
    lua_rawget(L, idx);
    BOOL is_ref = NO;
    if (lua_isstring(L, -1)) {
        const char * style = lua_tostring(L, -1);
        is_ref = strcmp("by_reference", style) == 0;
    }
    lua_pop(L, 1);
    
    lua_pushstring(L, "__swift_obj");
    lua_rawget(L, idx);
    
    id obj = nil;
    if (is_ref) {
        void * ud = lua_touserdata(L, -1);
        obj = (__bridge id) ud;
    } else {
        void** ud = (void**)lua_touserdata(L, -1); // on top, there might be args between bottom and top
        obj = (__bridge id)(*ud); // obj, ptr
    }
    
    lua_pop(L, 1); // obj
    return obj;
}

/*static void * to_obj_ptr(lua_State * L, int index) {
    lua_getfield(L, index, "__swift_obj");
    void** ud = (void**)lua_touserdata(L, -1); // on top, there might be args between bottom and top

    void * ptr = (*ud); // obj, ptr
    lua_pop(L, 1); // obj

    return ptr;
}*/

int call_objc(lua_State * L, Method method, Class cls) {
    assert(lua_istable(L, 1));
    id obj = to_obj(L, 1);

    SEL sel = method_getName(method);
    NSMethodSignature * sig = [obj methodSignatureForSelector: sel];
    assert(sig);

    SLog(@"lua stack top: %d", lua_gettop(L));

    return do_call(L, obj, method, sig);
}

// tbl, key, value
void set_ivar(lua_State * L, Class cls, NSString * name) {
    NSString * key = name;

    id obj = to_obj(L, 1);
    // void * ptr = to_obj_ptr(L, 1);

    objc_property_t prop = class_getProperty(cls, key.UTF8String);
    // "T@\"NSArray\",N,C,Vnodes"
    NSString * encoding = [NSString stringWithUTF8String: property_getAttributes(prop)];
    SLog(@"set ivar, encoding for %@ is: %@", name, encoding);

    // ref: http://stackoverflow.com/questions/3497625/in-objective-c-determine-if-a-property-is-an-int-float-double-nsstring-nsdat/3497822#3497822
    if ([encoding hasPrefix: @"T"]) {
        encoding = [encoding substringWithRange: NSMakeRange(1, 1)];
    } else {
        assert(false);
    }

    int len = 0;
    void * buf = [Wax toObjc: L type: encoding.UTF8String stackIndex: 3 len: &len];

    char code = [encoding characterAtIndex: 0];
    if (code == _C_ID) {
        id val = (__bridge id) (*(void **)buf);
        // SLog(@"pre set: %ld", CFGetRetainCount((__bridge CFTypeRef) val));
        // id val = (__bridge_transfer id)(*(void **)buf);
        [obj setValue: val forKey: name];
        // id back = [obj valueForKey: name];
        // SLog(@"post set: %ld %ld", CFGetRetainCount((__bridge CFTypeRef) val), CFGetRetainCount((__bridge CFTypeRef) back));
    } else {
        SEL setter = [cls setterForPropertyWithName: name];

        switch (code) {
            case _C_LNG:
                inf_objc_msgSend(obj, setter, *(long *)buf);
                break;
            case _C_LNG_LNG:
                inf_objc_msgSend(obj, setter, *(long long *)buf);
                break;
            case _C_CHR:
                inf_objc_msgSend(obj, setter, *(char *)buf);
                break;
            case _C_SHT:
                inf_objc_msgSend(obj, setter, *(short *)buf);
                break;
            default:
                assert(false && "add more type");
        }
    }

    free(buf);

    /*Ivar ivar = class_getInstanceVariable(cls, name.UTF8String);
    if (ivar == nil) {
        key = [@"_" stringByAppendingString: name];
        ivar = class_getInstanceVariable(cls, key.UTF8String);
    }
    assert(ivar != nil);*/

    /*
    // http://alanduncan.me/2013/10/02/set-an-ivar-via-the-objective-c-runtime/
    ptrdiff_t offset = ivar_getOffset(ivar);
    NSLog(@"%p len %d, offset %ld", ptr, len, offset);
    memcpy((char *)ptr + offset, buf, len);*/

    /*
    // failed to make object_setIvar work ...
    id val = (__bridge id) (*(void **)buf);
    NSLog(@"set on %@, val: (%p) %@", obj, val, val);
    object_setIvar(obj, ivar, val);

    id back = object_getIvar(obj, ivar);
    assert(back == val);
    id ret = [obj valueForKey: key];
    NSLog(@"get back (%@): %p, %p", key, back, ret);
    assert(ret == val);*/
}

static int do_call(lua_State * L, id obj, Method method, NSMethodSignature * sig) {
    // for struct type, the length may be well over 10,
    // turn on AddressSanitizer to catch this stack frame scribble
    char * ret_type = method_copyReturnType(method);
    method_getReturnType(method, ret_type, sizeof(ret_type));
    int has_ret = ret_type[0] != _C_VOID;

    unsigned int n_arg = method_getNumberOfArguments(method);

    NSInvocation * invoke = [NSInvocation invocationWithMethodSignature: sig];
    invoke.target = obj;
    invoke.selector = method_getName(method);

    // wax_printStack(L, @"before extracting args");
    for (int i = 2; i < n_arg; ++i) {
        char * arg_type = method_copyArgumentType(method, i);
        // NSLog(@"%d) %s", i, arg_type);
        int len = 0;
        void * arg = [Wax toObjc: L type: arg_type stackIndex: i len: &len];
        // @doc:
        // This method copies the contents of buffer as the argument at index.
        // The number of bytes copied is determined by the argument size.
        [invoke setArgument: arg atIndex: i];

        free(arg_type);
        free(arg);
    }

    [invoke invoke];

    if (has_ret) {
        NSUInteger ret_len = [invoke.methodSignature methodReturnLength];
        void * ret_buf = calloc(1, ret_len);
        [invoke getReturnValue: ret_buf];

        [Wax fromObjc: L type: ret_type buffer: ret_buf];
        free(ret_buf);
    }

    free(ret_type);
    
    return has_ret;
}

void init_super(NSObject * obj) {
    struct objc_super spr = {
        obj,
        class_getSuperclass(object_getClass(obj))
    };

    ((void (*)(void *, SEL))objc_msgSendSuper)(&spr, @selector(init));
}

void after(NSObject * obj) {
    /*if ([obj conformsToProtocol: @protocol(UITableViewDataSource)]) {
        NSLog(@"%@ => UITableViewDataSource: %d %d %d", obj,
              [obj respondsToSelector: @selector(tableView:numberOfRowsInSection:)],
              [obj respondsToSelector: @selector(numberOfSectionsInTableView:)],
              [obj respondsToSelector: @selector(tableView:cellForRowAtIndexPath:)]);
    }*/
}

void add_alloc_zone(Class meta_class) {

}

typedef void (^ Pusher)(lua_State * L, void *);
typedef void (^ Loader)(lua_State * L, NSInvocation *);

@interface Forwarder ()

@property (nonatomic) NSDictionary<NSString *, Pusher> * pushers;
@property (nonatomic) NSDictionary<NSString *, Loader> * loaders;

@end

@implementation Forwarder

// @ref: objc type encoding https://developer.apple.com/library/content/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html
- (instancetype) init: (lua_State *) L {
    if (self = [super init]) {
        self.L = L;
    }
    return self;
}

- (void) callLuaFunction: (NSInvocation *) invoke {
    lua_State * t_L = [[NSThread currentThread] L];
    [self.class callLuaFunction: t_L invoke: invoke];
}

+ (void) callLuaFunction: (lua_State *) L invoke: (NSInvocation *) invoke {
    wax_printStack(L, @"before insert eh");
    // func, self
    int eh_pos = lua_gettop(L) - 1;
    lua_pushcfunction(L, error_handler); // func, self, eh
    lua_insert(L, eh_pos); // eh, func, self
    wax_printStack(L, @"after insert eh");

    NSMethodSignature * sig = invoke.methodSignature;
    const int n_default_arg = 2; // obj, _cmd
    for (int i = n_default_arg; i < sig.numberOfArguments; ++i) {
        NSString * arg_type = [NSString stringWithUTF8String: [sig getArgumentTypeAtIndex: i]];
        SLog(@"arg %d) %@", i, arg_type);
        void * arg = nil;
        [invoke getArgument: &arg atIndex: i];

        [Wax fromObjc: L type: arg_type.UTF8String buffer: &arg];
    }

    int n_ret = sig.methodReturnLength > 0 ? 1 : 0;
    int n_arg = (int)(sig.numberOfArguments - n_default_arg);

    // 1 for self, error handler is below func
    int ret = lua_pcall(L, 1 + n_arg, n_ret, eh_pos);

    // remove error handler
    lua_remove(L, eh_pos);

    if (ret != LUA_OK) {
        const char * err = lua_tostring(L, -1);
        SLog(@"failed to call: %d, %s", ret, err);
        assert(false);
    } else {
        if (n_ret == 1) {
            // @autoreleasepool {
            int len = 0;
                void * ret = [Wax toObjc: L type: sig.methodReturnType stackIndex: -1 len: &len];
                // doc:
                // An untyped buffer whose contents are copied as the receiver's return value.
                [invoke setReturnValue: ret];

                free(ret);
            // }
            // pop off ret
            lua_pop(L, 1);
        }
    }
}

@end
