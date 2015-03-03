//
//  ViewController.m
//  NTURLCache
//
//  Created by Javier Cardenete Morales on 03/03/15.
//  Copyright (c) 2015 Cardechnology. All rights reserved.
//

#import "ViewController.h"
#import "AFHTTPRequestOperationManager.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}

- (IBAction)request {
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    manager.requestSerializer = [AFHTTPRequestSerializer serializer];
    manager.requestSerializer.cachePolicy = NSURLRequestUseProtocolCachePolicy;
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    manager.responseSerializer.acceptableContentTypes = [NSSet setWithObject:@"text/html"];
    NSString *requestString = @"http://developers.google.com/web/fundamentals/performance/optimizing-content-efficiency/http-caching/?hl=en";
    NSDictionary *params = @{};
    
    BOOL __block responseFromCache = YES; // yes by default
    
    id (^requestCacheResponseBlock)(NSURLConnection *connection, NSCachedURLResponse *cachedResponse) =
    ^(NSURLConnection *connection, NSCachedURLResponse *cachedResponse) {
        responseFromCache = NO;
        return cachedResponse;
    };
    
    void (^requestSuccessBlock)(AFHTTPRequestOperation *operation, id responseObject) =
    ^(AFHTTPRequestOperation *operation, id responseObject) {
        NSLog(@"SUCCESS %i", responseFromCache);
        self.labelResult.text = [NSString stringWithFormat:@"Response from cache? %i", responseFromCache];
    };
    
    void (^requestFailureBlock)(AFHTTPRequestOperation *operation, NSError *error) =
    ^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"ERROR: %@ %i", error, responseFromCache);
        self.labelResult.text = [NSString stringWithFormat:@"Error. Response from cache? %i", responseFromCache];
        
        // If offline, always try to get from the Cache
        if (error.code == -1009) {
            manager.requestSerializer.cachePolicy = NSURLRequestReturnCacheDataDontLoad;
            AFHTTPRequestOperation *cacheOperation = [manager GET:requestString
                                                       parameters:params
                                                          success:requestSuccessBlock
                                                          failure:requestFailureBlock];
            [cacheOperation setCacheResponseBlock:requestCacheResponseBlock];
        }
    };
    
    AFHTTPRequestOperation *operation = [manager GET:requestString
                                          parameters:params
                                             success:requestSuccessBlock
                                             failure:requestFailureBlock];
    [operation setCacheResponseBlock:requestCacheResponseBlock];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
