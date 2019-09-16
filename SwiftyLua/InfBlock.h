//
//  Block.h
//  SwiftyLua
//
//  Created by hanzhao on 2017/5/16.
//  Copyright © 2017年 hanzhao. All rights reserved.
//

// #import <Foundation/Foundation.h>

// @ref: http://stackoverflow.com/questions/9048305/checking-objective-c-block-type
// doesn't work for swift block
const char * block_sig(id blockObj);

// @ref: https://github.com/ebf/CTObjectiveCRuntimeAdditions
// another attempt
NSMethodSignature * block_signature(id blockObj);
