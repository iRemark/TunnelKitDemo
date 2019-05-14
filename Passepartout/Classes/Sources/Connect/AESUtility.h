//
//  AESUtility.h
//  BasicTunnel-iOS
//
//  Created by Thor on 2018/12/4.
//  Copyright © 2018 Davide De Rosa. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *key = @"panda&beta#12345";

@interface AESUtility : NSObject
    
+ (NSString *)EncryptString:(NSString *)sourceStr;
    
+ (NSString *)DecryptString:(NSString *)secretStr;
    
@end

NS_ASSUME_NONNULL_END
