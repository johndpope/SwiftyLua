//
//  ClassForwarder.h
//  SwiftyLua
//
//  Created by hanzhao on 2017/3/3.
//  Copyright © 2017年 hanzhao. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Forwarder.h"

@interface ClassForwarder : Forwarder

- (instancetype) init: (lua_State *) L class: (Class) cls_addr;

@end
