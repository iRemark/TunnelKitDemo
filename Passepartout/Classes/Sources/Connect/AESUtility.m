//
//  AESUtility.m
//  BasicTunnel-macOS
//
//  Created by Thor on 2018/12/4.
//  Copyright © 2018 Davide De Rosa. All rights reserved.
//

#import "AESUtility.h"
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonCryptor.h>


@implementation AESUtility
    
+ (NSString *)EncryptString:(NSString *)sourceStr
    {
        char keyPtr[kCCKeySizeAES256 + 1];
        bzero(keyPtr, sizeof(keyPtr));
        [key getCString:keyPtr maxLength:sizeof(keyPtr) encoding:NSUTF8StringEncoding];
        
        NSData *sourceData = [sourceStr dataUsingEncoding:NSUTF8StringEncoding];
        NSUInteger dataLength = [sourceData length];
        size_t buffersize = dataLength + kCCBlockSizeAES128;
        void *buffer = malloc(buffersize);
        size_t numBytesEncrypted = 0;
        CCCryptorStatus cryptStatus = CCCrypt(kCCEncrypt, kCCAlgorithmAES128, kCCOptionPKCS7Padding | kCCOptionECBMode, keyPtr, kCCBlockSizeAES128, NULL, [sourceData bytes], dataLength, buffer, buffersize, &numBytesEncrypted);
        
        if (cryptStatus == kCCSuccess) {
            NSData *encryptData = [NSData dataWithBytesNoCopy:buffer length:numBytesEncrypted];
            //对加密后的二进制数据进行base64转码
            return [encryptData base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithLineFeed];
        }
        else
        {
            free(buffer);
            return nil;
        }
    }
    
+ (NSString *)DecryptString:(NSString *)secretStr
    {
        //先对加密的字符串进行base64解码
        NSData *decodeData = [[NSData alloc] initWithBase64EncodedString:secretStr options:NSDataBase64DecodingIgnoreUnknownCharacters];
        
        char keyPtr[kCCKeySizeAES256 + 1];
        bzero(keyPtr, sizeof(keyPtr));
        [key getCString:keyPtr maxLength:sizeof(keyPtr) encoding:NSUTF8StringEncoding];
        
        NSUInteger dataLength = [decodeData length];
        size_t bufferSize = dataLength + kCCBlockSizeAES128;
        void *buffer = malloc(bufferSize);
        size_t numBytesDecrypted = 0;
        CCCryptorStatus cryptStatus = CCCrypt(kCCDecrypt, kCCAlgorithmAES128, kCCOptionPKCS7Padding | kCCOptionECBMode, keyPtr, kCCBlockSizeAES128, NULL, [decodeData bytes], dataLength, buffer, bufferSize, &numBytesDecrypted);
        if (cryptStatus == kCCSuccess) {
            NSData *data = [NSData dataWithBytesNoCopy:buffer length:numBytesDecrypted];
            NSString *result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            return result;
        }
        else
        {
            free(buffer);
            return nil;
        }
    }
    @end


