//
//  NTURLCache.h
//  NTURLCache
//
//  Created by Javier Cardenete Morales on 03/03/15.
//  Copyright (c) 2015 Cardechnology. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FMDB.h"

@interface NTURLCache : NSURLCache

@property(nonatomic,strong) FMDatabase *db;

- (void)deleteRequest:(NSString *)requestString;

@end



