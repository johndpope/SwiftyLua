//
//  RefHolder.m
//  SwiftyLua
//
//  Created by Zhao Han on 9/20/18.
//  Copyright © 2018 hanzhao. All rights reserved.
//

#import "RefHolder.h"

@implementation RefHolder

+ (id) holdWithAutorelease: (id) obj {
    CFAutorelease((__bridge CFTypeRef)(obj));
    return obj;
}

@end
