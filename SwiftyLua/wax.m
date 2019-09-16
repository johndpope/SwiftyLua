//
//  wax.m
//  SwiftyLua
//
//  Created by hanzhao on 2017/3/30.
//  Copyright © 2017年 hanzhao. All rights reserved.
//

#import "wax.h"
#import <objc/runtime.h>
#import <SwiftyLua/SwiftyLua-Swift.h>
#import "Forwarder.h"
#import "InfBlock.h"
#import "RefHolder.h"

static LogLevel s_level = LogLevelObjc;
typedef void (^ BLK) (void);

//#define _C_ATOM     '%'
//#define _C_VECTOR   '!'
//#define _C_CONST    'r'

// ENCODINGS CAN BE FOUND AT http://developer.apple.com/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html
#define WAX_TYPE_CHAR _C_CHR
#define WAX_TYPE_INT _C_INT
#define WAX_TYPE_SHORT _C_SHT
#define WAX_TYPE_UNSIGNED_CHAR _C_UCHR
#define WAX_TYPE_UNSIGNED_INT _C_UINT
#define WAX_TYPE_UNSIGNED_SHORT _C_USHT

#define WAX_TYPE_LONG _C_LNG
#define WAX_TYPE_LONG_LONG _C_LNG_LNG
#define WAX_TYPE_UNSIGNED_LONG _C_ULNG
#define WAX_TYPE_UNSIGNED_LONG_LONG _C_ULNG_LNG
#define WAX_TYPE_FLOAT _C_FLT
#define WAX_TYPE_DOUBLE _C_DBL

#define WAX_TYPE_C99_BOOL _C_BOOL

#define WAX_TYPE_STRING _C_CHARPTR
#define WAX_TYPE_VOID _C_VOID
#define WAX_TYPE_ARRAY _C_ARY_B
#define WAX_TYPE_ARRAY_END _C_ARY_E
#define WAX_TYPE_BITFIELD _C_BFLD
#define WAX_TYPE_ID _C_ID
#define WAX_TYPE_CLASS _C_CLASS
#define WAX_TYPE_SELECTOR _C_SEL
#define WAX_TYPE_STRUCT _C_STRUCT_B
#define WAX_TYPE_STRUCT_END _C_STRUCT_E
#define WAX_TYPE_UNION _C_UNION_B
#define WAX_TYPE_UNION_END _C_UNION_E
#define WAX_TYPE_POINTER _C_PTR
#define WAX_TYPE_UNKNOWN _C_UNDEF

#define WAX_PROTOCOL_TYPE_CONST 'r'
#define WAX_PROTOCOL_TYPE_IN 'n'
#define WAX_PROTOCOL_TYPE_INOUT 'N'
#define WAX_PROTOCOL_TYPE_OUT 'o'
#define WAX_PROTOCOL_TYPE_BYCOPY 'O'
#define WAX_PROTOCOL_TYPE_BYREF 'R'
#define WAX_PROTOCOL_TYPE_ONEWAY 'V'

static int wax_simplifyTypeDescription(const char *in, char *out);
static int wax_fromObjc(lua_State *L, const char *typeDescription, void *buffer);

static int wax_sizeOfTypeDescription(const char *full_type_description) {
    int index = 0;
    int size = 0;

    size_t length = strlen(full_type_description) + 1;
    char *type_description = alloca(length);
    bzero(type_description, length);
    wax_simplifyTypeDescription(full_type_description, type_description);

    while(type_description[index]) {
        switch (type_description[index]) {
            case WAX_TYPE_POINTER:
                size += sizeof(void *);
                break;//not need break?

            case WAX_TYPE_CHAR:
                size += sizeof(char);
                break;

            case WAX_TYPE_INT:
                size += sizeof(int);
                break;

            case WAX_TYPE_ARRAY:
            case WAX_TYPE_ARRAY_END:
                [NSException raise:@"Wax Error" format:@"C array's are not implemented yet."];
                break;

            case WAX_TYPE_SHORT:
                size += sizeof(short);
                break;

            case WAX_TYPE_UNSIGNED_CHAR:
                size += sizeof(unsigned char);
                break;

            case WAX_TYPE_UNSIGNED_INT:
                size += sizeof(unsigned int);
                break;

            case WAX_TYPE_UNSIGNED_SHORT:
                size += sizeof(unsigned short);
                break;

            case WAX_TYPE_LONG:
                size += sizeof(long);
                break;

            case WAX_TYPE_LONG_LONG:
                size += sizeof(long long);
                break;

            case WAX_TYPE_UNSIGNED_LONG:
                size += sizeof(unsigned long);
                break;

            case WAX_TYPE_UNSIGNED_LONG_LONG:
                size += sizeof(unsigned long long);
                break;

            case WAX_TYPE_FLOAT:
                size += sizeof(float);
                break;

            case WAX_TYPE_DOUBLE:
                size += sizeof(double);
                break;

            case WAX_TYPE_C99_BOOL:
                size += sizeof(_Bool);
                break;

            case WAX_TYPE_STRING:
                size += sizeof(char *);
                break;

            case WAX_TYPE_VOID:
                size += sizeof(char);
                break;

            case WAX_TYPE_BITFIELD:
                [NSException raise:@"Wax Error" format:@"Bitfields are not implemented yet"];
                break;

            case WAX_TYPE_ID:
                size += sizeof(id);
                break;

            case WAX_TYPE_CLASS:
                size += sizeof(Class);
                break;

            case WAX_TYPE_SELECTOR:
                size += sizeof(SEL);
                break;

            case WAX_TYPE_STRUCT:
            case WAX_TYPE_STRUCT_END:
            case WAX_TYPE_UNION:
            case WAX_TYPE_UNION_END:
            case WAX_TYPE_UNKNOWN:
            case WAX_PROTOCOL_TYPE_CONST:
            case WAX_PROTOCOL_TYPE_IN:
            case WAX_PROTOCOL_TYPE_INOUT:
            case WAX_PROTOCOL_TYPE_OUT:
            case WAX_PROTOCOL_TYPE_BYCOPY:
            case WAX_PROTOCOL_TYPE_BYREF:
            case WAX_PROTOCOL_TYPE_ONEWAY:

                // Weeeee! Just ignore this stuff I guess?
                break;
            default:
                [NSException raise:@"Wax Error" format:@"Unknown type encoding %c", type_description[index]];
                break;
        }

        index++;
    }
    return size;
}


static int wax_simplifyTypeDescription(const char *in, char *out) {
    int out_index = 0;
    int in_index = 0;
    if(strlen(in) >= 2 && in[0] == WAX_TYPE_ID && in[1] == '\"'){//sig in block. eg: @\"NSString\"
        out[0] = WAX_TYPE_ID;
        out[1] = 0;
        return 2;
    }
    while(in[in_index]) {
        switch (in[in_index]) {
            case WAX_TYPE_STRUCT:
            case WAX_TYPE_UNION:
                for (; in[in_index] != '='; in_index++); // Eat the name!
                in_index++; // Eat the = sign
                break;

            case WAX_TYPE_ARRAY:
                do {
                    out[out_index++] = in[in_index++];
                } while(in[in_index] != WAX_TYPE_ARRAY_END);
                break;

            case WAX_TYPE_POINTER: { //get rid of internal stucture parts
                out[out_index++] = in[in_index++];
                for (; in[in_index] == '^'; in_index++); // Eat all the pointers

                switch (in[in_index]) {
                    case WAX_TYPE_UNION:
                    case WAX_TYPE_STRUCT: {
                        in_index++;
                        int openCurlies = 1;

                        for (; openCurlies > 1 || (in[in_index] != WAX_TYPE_UNION_END && in[in_index] != WAX_TYPE_STRUCT_END); in_index++) {
                            if (in[in_index] == WAX_TYPE_UNION || in[in_index] == WAX_TYPE_STRUCT) openCurlies++;
                            else if (in[in_index] == WAX_TYPE_UNION_END || in[in_index] == WAX_TYPE_STRUCT_END) openCurlies--;
                        }
                        break;
                    }
                }
            }

            case WAX_TYPE_STRUCT_END:
            case WAX_TYPE_UNION_END:
            case '0':
            case '1':
            case '2':
            case '3':
            case '4':
            case '5':
            case '6':
            case '7':
            case '8':
            case '9':
                in_index++;
                break;

            default:
                out[out_index++] = in[in_index++];
                break;
        }
    }
    
    out[out_index] = '\0';
    
    return out_index;
}


#define WAX_TO_INTEGER(_type_) *outsize = sizeof(_type_); value = calloc(sizeof(_type_), 1); *((_type_ *)value) = (_type_)lua_tointeger(L, stackIndex);
#define WAX_TO_NUMBER(_type_) *outsize = sizeof(_type_); value = calloc(sizeof(_type_), 1); *((_type_ *)value) = (_type_)lua_tonumber(L, stackIndex);
#define WAX_TO_BOOL_OR_CHAR(_type_) *outsize = sizeof(_type_); value = calloc(sizeof(_type_), 1); *((_type_ *)value) = (_type_)( lua_isstring(L, stackIndex) ? lua_tostring(L, stackIndex)[0] : lua_toboolean(L, stackIndex));


// MAKE SURE YOU RELEASE THE RETURN VALUE!
static void * wax_copyToObjc(lua_State *L, const char *typeDescription, int stackIndex, int *outsize) {
    void *value = nil;

    // Ignore method encodings
    switch (typeDescription[0]) {
        case WAX_PROTOCOL_TYPE_CONST:
        case WAX_PROTOCOL_TYPE_IN:
        case WAX_PROTOCOL_TYPE_INOUT:
        case WAX_PROTOCOL_TYPE_OUT:
        case WAX_PROTOCOL_TYPE_BYCOPY:
        case WAX_PROTOCOL_TYPE_BYREF:
        case  WAX_PROTOCOL_TYPE_ONEWAY:
            typeDescription = typeDescription + 1; // Skip first
            break;
    }


    if (outsize == nil) {
        outsize = alloca(sizeof(int)); // if no outsize address set, treat it as a junk var
    }

    switch (typeDescription[0]) {
        case WAX_TYPE_VOID://Convenient and unified treatment of the return value
            *((int*)value) = 0;
            break;

        case WAX_TYPE_C99_BOOL:
            WAX_TO_BOOL_OR_CHAR(BOOL)
            break;

        case WAX_TYPE_CHAR:
            *outsize = sizeof(char); value = calloc(sizeof(char), 1);
            if(lua_type(L, stackIndex) == LUA_TNUMBER){//There should be corresponding with wax_fromObjc, otherwise the incoming char by wax_fromObjc into number, and then through the wax_copyToObjc into strings are truncated.（如'a'->97->'9'）
                *((char *)value) = (char)lua_tonumber(L, stackIndex);
            }else if(lua_type(L, stackIndex) == LUA_TSTRING){
                *((char *)value) = (char)lua_tostring(L, stackIndex)[0];
            }else{//32 bit BOOL is char
                *((char *)value) = (char)lua_toboolean(L, stackIndex);
            }
            break;

        case WAX_TYPE_INT:
            WAX_TO_INTEGER(int)
            break;

        case WAX_TYPE_SHORT:
            WAX_TO_INTEGER(short)
            break;

        case WAX_TYPE_UNSIGNED_CHAR:
            WAX_TO_INTEGER(unsigned char)
            break;

        case WAX_TYPE_UNSIGNED_INT:
            WAX_TO_INTEGER(unsigned int)
            break;

        case WAX_TYPE_UNSIGNED_SHORT:
            WAX_TO_INTEGER(unsigned short)
            break;

        case WAX_TYPE_LONG:
            WAX_TO_NUMBER(long)
            break;

        case WAX_TYPE_LONG_LONG:
            if (lua_getmetatable(L, stackIndex) == 1) {
                // check enum
                assert(lua_istable(L, -1));

                lua_getfield(L, -1, "__note");
                const char * note = luaL_checkstring(L, -1);
                if (strcmp(note, "enum") == 0) {
                    lua_pop(L, 2); // pop off: meta, "enum"

                    // lua_getfield(L, -1, "__name");

                    // copy from enum to number
                    size_t len = lua_rawlen(L, -1);

                    if ((sizeof(long long) == len)) {
                        void * ptr = lua_touserdata(L, -1);
                        // long long val = *(long long *)ptr;
                        // enum is const, no need to malloc
                        value = calloc(len, 1);
                        memcpy(value, ptr, len);
                    } else {
                        SLog(@"len is: %zu", len);
                        wax_printStack(L, @"failed to get enum");
                        assert(false);
                    }
                } else {
                    assert(false && note);
                }

            } else {
                WAX_TO_NUMBER(long long)
            }
            break;

        case WAX_TYPE_UNSIGNED_LONG:
            WAX_TO_NUMBER(unsigned long)
            break;

        case WAX_TYPE_UNSIGNED_LONG_LONG:
            WAX_TO_NUMBER(unsigned long long);
            break;

        case WAX_TYPE_FLOAT:
            WAX_TO_NUMBER(float);
            break;

        case WAX_TYPE_DOUBLE:
            WAX_TO_NUMBER(double);
            break;

        case WAX_TYPE_SELECTOR:
            if (lua_isnil(L, stackIndex)) { // If no slector is passed it, just use an empty string
                lua_pushstring(L, "");
                lua_replace(L, stackIndex);
            }

            *outsize = sizeof(SEL);
            value = calloc(sizeof(SEL), 1);
            const char *selectorName = luaL_checkstring(L, stackIndex);
            *((SEL *)value) = sel_getUid(selectorName);

            break;

        case WAX_TYPE_CLASS:
            *outsize = sizeof(Class);
            value = calloc(sizeof(Class), 1);
            if (lua_isuserdata(L, stackIndex)) {
                void * ud = lua_touserdata(L, stackIndex);
                *((Class *)value) = (__bridge Class)ud;
            } else if (lua_istable(L, stackIndex)) {
                wax_printStack(L, @"class stack");
                lua_getfield(L, stackIndex, "__swift_obj");

                void * data = lua_touserdata(L, -1);
                id obj = (__bridge id)data;
                *(__strong id *)value = obj;

                SLog(@"to objc: %@", obj);
            }else {
                *((Class *)value) = objc_getClass(lua_tostring(L, stackIndex));
            }
            break;

        case WAX_TYPE_STRING: {
            //Here is the address of the string value should be, and should not be the contents of the string itself
            //            const char *string = lua_tostring(L, stackIndex);
            //            int length = strlen(string) + 1;
            //            *outsize = length;
            //
            //            value = calloc(sizeof(char *), length);
            //            strcpy(value, string);

            const char *string = lua_tostring(L, stackIndex);
            *outsize = sizeof(char*);

            value = calloc(sizeof(char *), 1);

            memcpy(value, &string, *outsize);
            break;
        }

        case WAX_TYPE_POINTER:
            *outsize = sizeof(void *);

            value = calloc(sizeof(void *), 1);
            void *pointer = nil;

            switch (typeDescription[1]) {
                case WAX_TYPE_VOID:
                case WAX_TYPE_ID: {
                    switch (lua_type(L, stackIndex)) {
                        case LUA_TNIL:
                        case LUA_TNONE:
                            break;
                        case LUA_TTABLE: {
                            lua_getfield(L, stackIndex, "__swift_obj");
                            void * obj = lua_touserdata(L, -1);
                            lua_pop(L, 1);

                            pointer = obj;
                        }break;

                        case LUA_TUSERDATA: {
                            /*wax_instance_userdata *instanceUserdata = (wax_instance_userdata *)luaL_checkudata(L, stackIndex, WAX_INSTANCE_METATABLE_NAME);

                            if (typeDescription[1] == WAX_TYPE_VOID) {
                                pointer = instanceUserdata->instance;
                            }
                            else {
                                pointer = &instanceUserdata->instance;
                            }*/

                            break;
                        }
                        case LUA_TLIGHTUSERDATA:
                            pointer = lua_touserdata(L, stackIndex);
                            break;
                        default:
                            luaL_error(L, "Can't convert %s to wax_instance_userdata.", luaL_typename(L, stackIndex));
                            break;
                    }
                    break;
                }
                default:
                    if (lua_islightuserdata(L, stackIndex)) {
                        pointer = lua_touserdata(L, stackIndex);
                    }
                    else {
                        free(value);
                        luaL_error(L, "Converstion from %s to Objective-c not implemented.", typeDescription);
                    }
            }

            if (pointer) {
                memcpy(value, &pointer, *outsize);
            }

            break;

        case WAX_TYPE_ID: {
            *outsize = sizeof(id);

            value = calloc(sizeof(id), 1);
            // add number, string

            id instance = nil;

            switch (lua_type(L, stackIndex)) {
                case LUA_TNIL:
                case LUA_TNONE:
                    instance = nil;
                    break;

                case LUA_TBOOLEAN: {
                    BOOL value = lua_toboolean(L, stackIndex);
                    instance = [NSValue valueWithBytes:&value objCType:@encode(bool)];
                    break;
                }
                case LUA_TNUMBER:
                    instance = [NSNumber numberWithDouble:lua_tonumber(L, stackIndex)];
                    break;

                case LUA_TSTRING:
                    // @ref: http://lua-users.org/lists/lua-l/2001-08/msg00323.html
                    // "you must *not* free pointers returned by lua_tostring"
                    instance = [NSString stringWithUTF8String:lua_tostring(L, stackIndex)];
                    break;

                case LUA_TTABLE: {
                    // check if it's an object
                    lua_getfield(L, stackIndex, "__swift_obj");
                    if (lua_isuserdata(L, -1)) {
                        // size_t len = lua_rawlen(L, -1);
                        int type = lua_type(L, -1);
                        if (type == LUA_TLIGHTUSERDATA) {
                            // light userdata
                            void * obj = lua_touserdata(L, -1);
                            lua_pop(L, 1);
                            
                            instance = (__bridge id)obj;
                        } else {
                            assert(type == LUA_TUSERDATA);
                            void ** obj = (void **)lua_touserdata(L, -1);
                            lua_pop(L, 1);

                            // expicitly give up life time management (transfer to app side)
                            // ??? will this cause issue when the obj is passing back to lua?
                            instance = (__bridge id)(*obj);
                            // *(void **)value = *obj;
                        }
                        break;
                    } else {
                        assert(lua_isnil(L, -1));
                        lua_pop(L, 1);
                    }

                    BOOL dictionary = NO;

                    lua_pushvalue(L, stackIndex); // Push the table reference on the top
                    lua_pushnil(L);  /* first key */
                    while (!dictionary && lua_next(L, -2)) {
                        if (lua_type(L, -2) != LUA_TNUMBER) {
                            dictionary = YES;
                            lua_pop(L, 2); // pop key and value off the stack
                        }
                        else {
                            lua_pop(L, 1);
                        }
                    }

                    if (dictionary) {
                        instance = [NSMutableDictionary dictionary];

                        lua_pushnil(L);  /* first key */
                        while (lua_next(L, -2)) {
                            void ** key = wax_copyToObjc(L, "@", -2, nil);
                            
                            // type of value
                            void ** object = nil;
                            switch(lua_type(L, -1)) {
                                case LUA_TNUMBER:
                                    if (lua_isinteger(L, -1)) {
                                        char desc[] = {WAX_TYPE_INT, '\0'};
                                        object = wax_copyToObjc(L, desc, -1, nil);
                                    } else {
                                        char desc[] = {WAX_TYPE_DOUBLE, '\0'};
                                        object = wax_copyToObjc(L, desc, -1, nil);
                                    }
                                    [instance setObject: (__bridge id)*object forKey: (__bridge id)*key];
                                    break;
                                case LUA_TBOOLEAN:
                                    [instance setObject: [NSNumber numberWithBool: lua_toboolean(L, -1)] forKey: (__bridge id)*key];
                                    break;
                                case LUA_TSTRING:
                                case LUA_TTABLE:{
                                    char desc[] = {WAX_TYPE_ID, '\0'};
                                    object = wax_copyToObjc(L, desc, -1, nil);
                                    [instance setObject: (__bridge id)*object forKey: (__bridge id)*key];
                                    break;}
                                default:{
                                    char desc[] = {WAX_TYPE_ID, '\0'};
                                    object = wax_copyToObjc(L, desc, -1, nil);
                                    [instance setObject: (__bridge id)*object forKey: (__bridge id)*key];
                                    break;}
                            }
                            lua_pop(L, 1); // Pop off the value
                            free(key);
                            free(object);
                        }
                    }
                    else {
                        instance = [NSMutableArray array];

                        lua_pushnil(L);  /* first key */
                        while (lua_next(L, -2)) {
                            // int index = lua_tonumber(L, -2) - 1;
                            void ** object = wax_copyToObjc(L, "@", -1, nil);
                            // [instance insertObject: (__bridge id)(*object) atIndex:index];
                            [instance addObject: (__bridge id)(*object)];
                            lua_pop(L, 1);
                            free(object);
                        }
                    }

                    lua_pop(L, 1); // Pop the table reference off
                    break;
                }

                case LUA_TUSERDATA: {
                    // wax_instance_userdata *instanceUserdata = (wax_instance_userdata *)luaL_checkudata(L, stackIndex, WAX_INSTANCE_METATABLE_NAME);
                    // instance = instanceUserdata->instance;
                    assert(false);

                    break;
                }
                case LUA_TLIGHTUSERDATA: {
                    instance = (__bridge id)lua_touserdata(L, -1);
                    break;
                }
                case LUA_TFUNCTION: {
                    if (0) {
                        // instance = [[WaxFunction alloc] init];
                        // wax_instance_create(L, instance, NO);
                        // !!!
                        assert(false);

                        lua_pushvalue(L, -2);
                        lua_setfield(L, -2, "function"); // Stores function inside of this instance
                        lua_pop(L, 1);
                    }
                    __block BLK blk = nil;
                    blk = ^ {
                        // SLog(@"in the block: %s", block_sig(blk));
                        assert(false);
                    };

                    instance = blk;

                    break;
                }
                default:
                    luaL_error(L, "Can't convert %s to obj-c.", luaL_typename(L, stackIndex));
                    break;
            }

            if (instance) {
                *(__autoreleasing id *)value = instance;
                // *(void **)value = (__bridge void *)(instance);
                
            } else {
                // passing nil
                // ...
            }


            break;
        }

        case WAX_TYPE_STRUCT: {
            if (lua_isuserdata(L, stackIndex)) {
                //wax_struct_userdata *structUserdata = (wax_struct_userdata *)luaL_checkudata(L, stackIndex, WAX_STRUCT_METATABLE_NAME);
                // value = malloc(structUserdata->size);
                // memcpy(value, structUserdata->data, structUserdata->size);
                // !!!
                assert(false);
            } else if (lua_istable(L, stackIndex)) {
                lua_getfield(L, stackIndex, "__swift_obj"); // struct_ptr
                assert(lua_isuserdata(L, -1));
                void * struct_ptr = lua_touserdata(L, -1);
                size_t len = lua_rawlen(L, -1);
                assert(len > 0);

                value = malloc(len);
                memcpy(value, struct_ptr, len);

                lua_pop(L, 1);
            } else {
                void *data = (void *)lua_tostring(L, stackIndex);
                size_t length = lua_rawlen(L, stackIndex);
                *outsize = (int)length;
                
                value = malloc(length);
                memcpy(value, data, length);
            }
            break;
        }
            
        default:
            luaL_error(L, "Unable to get type for Obj-C method argument with type description '%s'", typeDescription);
            break;
    }
    
    return value;
}

NSRecursiveLock* wax_globalLock(){
    static NSRecursiveLock *globalLock = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        globalLock = [[NSRecursiveLock alloc] init];
    });
    return globalLock;
}

// I could get rid of this <- Then why don't you?
const char *wax_removeProtocolEncodings(const char *type_descriptions) {
    switch (type_descriptions[0]) {
        case WAX_PROTOCOL_TYPE_CONST:
        case WAX_PROTOCOL_TYPE_INOUT:
        case WAX_PROTOCOL_TYPE_OUT:
        case WAX_PROTOCOL_TYPE_BYCOPY:
        case WAX_PROTOCOL_TYPE_BYREF:
        case WAX_PROTOCOL_TYPE_ONEWAY:
            return &type_descriptions[1];
            break;
        default:
            return type_descriptions;
            break;
    }
}

static BOOL isStackBlock(id instance){
    NSString *des = NSStringFromClass([instance class]);
    if([des isEqualToString:@"__NSStackBlock__"]){
        return YES;
    }
    return NO;
}

#define BEGIN_STACK_MODIFY(L)      [wax_globalLock() lock];\
int __startStackIndex = lua_gettop((L));\

#define END_STACK_MODIFY(L, i) while(lua_gettop((L)) > (__startStackIndex + (i))) lua_remove((L), __startStackIndex + 1);\
[wax_globalLock() unlock];\

void wax_fromInstance(lua_State *L, id instance) {
    BEGIN_STACK_MODIFY(L)

    if (instance) {
        if ([instance isKindOfClass:[NSString class]]) {
            lua_pushstring(L, [(NSString *)instance UTF8String]);
        }
        else if ([instance isKindOfClass:[NSNumber class]]) {
            lua_pushnumber(L, [instance doubleValue]);
        }
        else if ([instance isKindOfClass:[NSArray class]]) {
            lua_newtable(L);
            for (id obj in instance) {
                int i = (int)lua_rawlen(L, -1);
                wax_fromInstance(L, obj);
                lua_rawseti(L, -2, i + 1);
            }
        }
        else if ([instance isKindOfClass:[NSDictionary class]]) {
            lua_newtable(L);
            for (id key in instance) {
                wax_fromInstance(L, key);
                wax_fromInstance(L, [instance objectForKey:key]);
                lua_rawset(L, -3);
            }
        }
        else if ([instance isKindOfClass:[NSValue class]]) {
            void *buffer = malloc(wax_sizeOfTypeDescription([instance objCType]));
            [instance getValue:buffer];
            wax_fromObjc(L, [instance objCType], buffer);
            free(buffer);
        }
// #warning WaxFunction misssing
        /*else if ([instance isKindOfClass:[WaxFunction class]]) {
            wax_instance_pushUserdata(L, instance);
            if (lua_isnil(L, -1)) {
                luaL_error(L, "Could not get userdata associated with WaxFunction");
            }
            lua_getfield(L, -1, "function");
        }*/else if (isStackBlock(instance)) {//stack block should copy,or gc will crash.
            // wax_instance_create(L, [instance copy], NO);
            SLog(@"create %@ in lua, line %d", instance, __LINE__);
            [SwiftyLua referenceNSObjWithL: L obj: instance type: ([instance class])];
        }
        else {
            // wax_instance_create(L, instance, ([instance class] == instance));//it maybe a class, eg:objc_getClass("Test.Swift"):init()
            if ([SwiftyLua findRegisteredWithL: L ptr: (void *)instance] == NO) {
                SLog(@"create obj %@ in lua, line %d", instance, __LINE__);
                [SwiftyLua referenceNSObjWithL: L obj: instance type: ([instance class])];
            } else {
                NSString * type = [SwiftyLua typeOf: L ptr: (void *)(instance)];
                SLog(@"%@ already registered in lua: %@", instance, type);
                NSString * real_class = [NSString stringWithCString: object_getClassName(instance) encoding: NSASCIIStringEncoding];
                
                NSArray * class_parts = [real_class componentsSeparatedByString: @"."];
                NSArray * core_data_parts = [class_parts.lastObject componentsSeparatedByString: @"_"];
                // core data class name are seperated by _ : e.g. InfinityExtKit.AssetNode_Asset_ (in class_entity_?)
                if (![[core_data_parts firstObject] isEqualToString: type]) {
                    NSLog(@"class mismatch for instance in reg and real type: %@ %@ != %@", real_class, core_data_parts, type);
                    
                    // the old obj is released by cocoa but it's release calling is not tracked by swiftylua
                    // .. reassociate with the new type
                    [SwiftyLua referenceNSObjWithL: L obj: instance type: ([instance class])];
                }
            }
        }
    }
    else {
        lua_pushnil(L);
    }
    
    END_STACK_MODIFY(L, 1)
}

int wax_typeOfDesc(const char * desc) {
    return wax_removeProtocolEncodings(desc)[0];
}

//change buffer to lua object and push stack, if it's OC object, then retain it.
static int wax_fromObjc(lua_State *L, const char *typeDescription, void *buffer) {
    BEGIN_STACK_MODIFY(L)

    typeDescription = wax_removeProtocolEncodings(typeDescription);

    int size = wax_sizeOfTypeDescription(typeDescription);

    switch (typeDescription[0]) {
        case WAX_TYPE_VOID:
            lua_pushnil(L);
            break;

        case WAX_TYPE_POINTER:
            lua_pushlightuserdata(L, *(void **)buffer);
            break;

        case WAX_TYPE_CHAR: {
            char c = *(char *)buffer;
            if (c <= 1) lua_pushboolean(L, c); // If it's 1 or 0, then treat it like a bool
            else lua_pushinteger(L, c);
            break;
        }

        case WAX_TYPE_SHORT:
            lua_pushinteger(L, *(short *)buffer);
            break;

        case WAX_TYPE_INT:
            lua_pushnumber(L, *(int *)buffer);
            break;

        case WAX_TYPE_UNSIGNED_CHAR:
            lua_pushnumber(L, *(unsigned char *)buffer);
            break;

        case WAX_TYPE_UNSIGNED_INT:
            lua_pushnumber(L, *(unsigned int *)buffer);
            break;

        case WAX_TYPE_UNSIGNED_SHORT:
            lua_pushinteger(L, *(short *)buffer);
            break;

        case WAX_TYPE_LONG:
            lua_pushnumber(L, *(long *)buffer);
            break;

        case WAX_TYPE_LONG_LONG:
            lua_pushnumber(L, *(long long *)buffer);
            break;

        case WAX_TYPE_UNSIGNED_LONG:
            lua_pushnumber(L, *(unsigned long *)buffer);
            break;

        case WAX_TYPE_UNSIGNED_LONG_LONG:
            lua_pushnumber(L, *(unsigned long long *)buffer);
            break;

        case WAX_TYPE_FLOAT:
            lua_pushnumber(L, *(float *)buffer);
            break;

        case WAX_TYPE_DOUBLE:
            lua_pushnumber(L, *(double *)buffer);
            break;

        case WAX_TYPE_C99_BOOL:
            lua_pushboolean(L, *(BOOL *)buffer);
            break;

        case WAX_TYPE_STRING:
            lua_pushstring(L, *(char **)buffer);
            break;

        case WAX_TYPE_ID: {
            void * ptr = *(void **)buffer;
            id instance = (__bridge id)ptr;
            // id instance = *(__strong id *) buffer;

            SLog(@"instance is: %@", instance);
            if (instance != nil) {
                wax_fromInstance(L, instance);
                
                // [RefHolder holdWithAutorelease: instance];
            } else {
                // allow passing nil
                lua_pushnil(L);
            }

            break;
        }

        case WAX_TYPE_STRUCT: {
            // wax_fromStruct(L, typeDescription, buffer);

            char * type = nil;
            if (typeDescription[0] == '{') { // We can get a name from the type desciption
                char *endLocation = strchr(&typeDescription[1], '=');
                if (endLocation) {
                    size_t size = endLocation - &typeDescription[1];
                    type = calloc(1, size + 1);
                    memcpy(type, typeDescription + 1, size);
                }
            } else {
                assert(false);
            }

            [SwiftyLua createNSStructWithL: L obj: buffer type: [NSString stringWithUTF8String: type] size: size];
            free(type);

            break;
        }

        case WAX_TYPE_SELECTOR:
            lua_pushstring(L, sel_getName(*(SEL *)buffer));
            break;

        case WAX_TYPE_CLASS: {
            Class cls = *(Class *)buffer;
            lua_pushlightuserdata(L, (__bridge void *)cls);

            break;
        }

        default:
            luaL_error(L, "Unable to convert Obj-C type with type description '%s'", typeDescription);
            break;
    }
    
    END_STACK_MODIFY(L, 1)
    
    return size;
}


/*static int call_index(lua_State * L) {
    return 0;
}*/

/*
static const struct luaL_Reg methods[] = {
    {"index_func", call_index},
    {NULL, NULL}
};*/

void luaopen_inf_wax (lua_State * L) {
    //luaL_register(L, INF_WAX_G, methods);
}

@implementation Wax

+ (int) sizeOfDesc: (const char *) desc {
    return wax_sizeOfTypeDescription(desc);
}

+ (void *) toObjc: (lua_State *) L type: (const char *) desc stackIndex: (int) index len: (int *) outsize {
    return wax_copyToObjc(L, desc, index, outsize);
}

+ (void) fromObjc: (lua_State *) L type: (const char *) desc buffer: (void *) buffer {
    wax_fromObjc(L, desc, buffer);
}

void compare_L(lua_State * lhs, lua_State * rhs) {
    assert(lhs->l_G == rhs->l_G);
}

@end

