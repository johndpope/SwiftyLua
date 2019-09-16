//
//  RefHolder.h
//  SwiftyLua
//
//  Created by Zhao Han on 9/20/18.
//  Copyright © 2018 hanzhao. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface RefHolder : NSObject

+ (id) holdWithAutorelease: (id) obj;

@end

