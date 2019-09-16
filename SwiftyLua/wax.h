//
//  wax.h
//  SwiftyLua
//
//  Created by hanzhao on 2017/3/30.
//  Copyright © 2017年 hanzhao. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <LuaSource/LuaSource.h>

// adapt from wax

#define INF_WAX_G "infwax"

@interface Wax : NSObject

+ (int) sizeOfDesc: (const char *) desc;
+ (void *) toObjc: (lua_State *) L type: (const char *) desc stackIndex: (int) index len: (int *) outsize;
+ (void) fromObjc: (lua_State *) L type: (const char *) desc buffer: (void *) buffer;
// + (void) luaLock: (lua_State *) L;

@end
