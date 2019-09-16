//
//  test.h
//  SwiftyLua
//
//  Created by hanzhao on 2018/4/13.
//  Copyright © 2018年 hanzhao. All rights reserved.
//

#ifndef macros_h
#define macros_h

// for type convering the objc_msgSend function at the calling point

#include <libextobjc/extobjc/metamacros.h>

#define my_type(arg)\
    __typeof__(arg)

#define the_type(idx, arg)\
    my_type(arg),

#define last_type(idx, arg)\
    my_type(arg)

#define inf_objc_msgSend(obj, sel, ...)\
    ((void (*)(id, SEL,\
        metamacro_if_eq(metamacro_argcount(__VA_ARGS__), 1) (my_type(__VA_ARGS__)) (\
        metamacro_foreach(the_type , , metamacro_take(metamacro_dec(metamacro_argcount(__VA_ARGS__)), __VA_ARGS__)) \
        metamacro_foreach(last_type , , metamacro_drop(metamacro_dec(metamacro_argcount(__VA_ARGS__)), __VA_ARGS__)) \
    )))objc_msgSend)(obj, sel, __VA_ARGS__)

#endif /* test_h */
