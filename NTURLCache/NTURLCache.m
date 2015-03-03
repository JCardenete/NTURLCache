//
//  NTURLCache.m
//  NTURLCache
//
//  Created by Javier Cardenete Morales on 03/03/15.
//  Copyright (c) 2015 Cardechnology. All rights reserved.
//

#import "NTURLCache.h"
#import "DateTools.h"
#import "AFNetworkReachabilityManager.h"


static NSDateFormatter* CreateDateFormatter(NSString *format)
{
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    NSLocale *locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
    
    [dateFormatter setLocale:locale];
    [dateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"GMT"]];
    [dateFormatter setDateFormat:format];
    
    return dateFormatter;
}

@interface NTURLCache (Private)

/*
 *
 */
- (BOOL)requestIsExpired:(NSDictionary *)responseObjectPlist;

/*
 *
 */
- (NSInteger)maxAgeFromCacheControlString:(NSString *)cacheControl;

/*
 * Parse HTTP Date: http://www.w3.org/Protocols/rfc2616/rfc2616-sec3.html#sec3.3.1
 */
+ (NSDate *)dateFromHttpDateString:(NSString *)httpDate;

@end

#define kCacheFolderPath @"/com.cardechnology.NTURLCache"


@implementation NTURLCache

- (id)initWithMemoryCapacity:(NSUInteger)memoryCapacity diskCapacity:(NSUInteger)diskCapacity diskPath:(NSString *)path {
    self = [super initWithMemoryCapacity:memoryCapacity diskCapacity:diskCapacity diskPath:path];
    if (self) {
        NSArray *docPaths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *dir = (NSString*)[docPaths objectAtIndex:0];
        dir = [dir stringByAppendingString:kCacheFolderPath];
        NSString *path = [dir stringByAppendingFormat:@"/Cache.db"];
        self.db = [[FMDatabase alloc] initWithPath:path];
        [self.db open];
    }
    return self;
}

- (NSCachedURLResponse *) cachedResponseForRequest:(NSURLRequest *)request {
    NSCachedURLResponse *cachedURLResponse = [super cachedResponseForRequest:request];
    if (cachedURLResponse == nil && [request.HTTPMethod isEqualToString:@"GET"] ) {
        FMResultSet *cfurl_cache_response = [self.db executeQuery:@"select * from cfurl_cache_response where request_key = ? limit 1", request.URL.absoluteString, nil];
        if ([cfurl_cache_response next]) {
            id entry_ID = [cfurl_cache_response objectForColumnName:@"entry_ID"];
            [cfurl_cache_response close];
            if (entry_ID != [NSNull null]) {
                FMResultSet *cfurl_cache_blob_data = [self.db executeQuery:@"select * from cfurl_cache_blob_data where entry_ID = ? limit 1", entry_ID, nil];
                if ([cfurl_cache_blob_data next]) {
                    id response_object = [cfurl_cache_blob_data objectForColumnName:@"response_object"];
                    [cfurl_cache_blob_data close];
                    FMResultSet *cfurl_receiver_data = [self.db executeQuery:@"select * from cfurl_cache_receiver_data where entry_ID = ? limit 1", entry_ID, nil];
                    if ([cfurl_receiver_data next]) {
                        id receiver_data = [cfurl_receiver_data objectForColumnName:@"receiver_data"];
                        int isDataOnFS = [cfurl_receiver_data intForColumn:@"isDataOnFS"];
                        
                        [cfurl_receiver_data close];
                        
                        NSString *error;
                        NSPropertyListFormat plistFormat;
                        id plist = (NSDictionary *)[NSPropertyListSerialization propertyListWithData:response_object
                                                                                             options:NSPropertyListImmutable
                                                                                              format:&plistFormat
                                                                                               error:&error];
                        
                        BOOL expired = [self requestIsExpired:(NSDictionary *)plist];
                        BOOL internetActive = [AFNetworkReachabilityManager sharedManager].reachable;
                        
                        if ( (!expired || !internetActive || request.cachePolicy==NSURLRequestReturnCacheDataDontLoad) && response_object != [NSNull null] && receiver_data != [NSNull null] && response_object && receiver_data) {
                            NSHTTPURLResponse *urlResponse = [[NSHTTPURLResponse alloc] initWithURL:request.URL MIMEType:[[request allHTTPHeaderFields] objectForKey:@"Accept"] expectedContentLength:[(NSData *)response_object length] textEncodingName:nil];
                            
                            // If the response is heavy, it will be saved in a file on the filesystem
                            if (isDataOnFS) {
                                NSArray *docPaths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
                                NSString *dir = (NSString*)[docPaths objectAtIndex:0];
                                NSString *path = [dir stringByAppendingFormat:@"%@/fsCachedData/%@", kCacheFolderPath, receiver_data];
                                
                                NSData *data = [NSData dataWithContentsOfFile:path];
                                
                                cachedURLResponse = [[NSCachedURLResponse alloc] initWithResponse:urlResponse data:data userInfo:nil storagePolicy:NSURLCacheStorageAllowed];
                            }
                            else {
                                cachedURLResponse = [[NSCachedURLResponse alloc] initWithResponse:urlResponse data:receiver_data userInfo:nil storagePolicy:NSURLCacheStorageAllowed];
                            }
                        }
                    }
                }
            }
        }
    }
    return cachedURLResponse;
}

-(void)storeCachedResponse:(NSCachedURLResponse *)cachedResponse forRequest:(NSURLRequest *)request
{
    if (request.cachePolicy != NSURLRequestReloadIgnoringLocalCacheData) {
        [super storeCachedResponse:cachedResponse forRequest:request];
    }
}

- (BOOL)requestIsExpired:(NSDictionary *)responseObjectPlist {
    NSArray *entries = [responseObjectPlist objectForKey:@"Array"];
    
    NSInteger maxAge = -1;
    NSDate *timestamp;
    for (NSObject *entry in entries)
    {
        if ([entry isKindOfClass:[NSDictionary class]]) {
            if ([entry valueForKey:@"Cache-Control"] != nil) {
                NSString *cacheControl = [entry valueForKey:@"Cache-Control"];
                maxAge = [self maxAgeFromCacheControlString:cacheControl];
            }
            
            if ([entry valueForKey:@"Date"] != nil) {
                timestamp = [NTURLCache dateFromHttpDateString:[entry valueForKey:@"Date"]];
            }
        }
    }
    
    NSDate *dateCurrent = [NSDate date];
    NSDate *dateLimit = [timestamp dateByAddingSeconds:maxAge];
    if ([dateCurrent isLaterThan:dateLimit] || maxAge==-1) {
        return YES;
    }
    else {
        return NO;
    }
    
}

- (NSInteger)maxAgeFromCacheControlString:(NSString *)cacheControl {
    NSInteger maxAge;
    NSRange foundRange = [cacheControl rangeOfString:@"max-age"];
    if (foundRange.length > 0)
    {
        NSScanner *cacheControlScanner = [NSScanner scannerWithString:cacheControl];
        [cacheControlScanner setScanLocation:foundRange.location + foundRange.length];
        [cacheControlScanner scanString:@"=" intoString:nil];
        [cacheControlScanner scanInteger:&maxAge];
    }
    
    return maxAge;
}

+ (NSDate *)dateFromHttpDateString:(NSString *)httpDate
{
    static NSDateFormatter *RFC1123DateFormatter;
    static NSDateFormatter *ANSICDateFormatter;
    static NSDateFormatter *RFC850DateFormatter;
    NSDate *date = nil;
    
    @synchronized(self)
    {
        if (!RFC1123DateFormatter) RFC1123DateFormatter = CreateDateFormatter(@"EEE, dd MMM yyyy HH:mm:ss z");
        date = [RFC1123DateFormatter dateFromString:httpDate];
        if (!date)
        {
            if (!ANSICDateFormatter) ANSICDateFormatter = CreateDateFormatter(@"EEE MMM d HH:mm:ss yyyy");
            date = [ANSICDateFormatter dateFromString:httpDate];
            if (!date)
            {
                if (!RFC850DateFormatter) RFC850DateFormatter = CreateDateFormatter(@"EEEE, dd-MMM-yy HH:mm:ss z");
                date = [RFC850DateFormatter dateFromString:httpDate];
            }
        }
    }
    
    return date;
}

@end

