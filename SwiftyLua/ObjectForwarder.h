//
//  SwiftObj.h
//  SwiftyLua
//
//  Created by hanzhao on 2017/2/26.
//  Copyright © 2017年 hanzhao. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Forwarder.h"

@protocol HelloProtocol <NSObject>

+ (id<HelloProtocol>) create;
- (void) hello;

@end

@interface ObjectForwarder : Forwarder

- (instancetype) init: (id) host L: (lua_State *) L;

@end
