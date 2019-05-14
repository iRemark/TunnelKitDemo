//
//  TLSBox.m
//  TunnelKit
//
//  Created by Davide De Rosa on 2/3/17.
//  Copyright (c) 2018 Davide De Rosa. All rights reserved.
//
//  https://github.com/keeshux
//
//  This file is part of TunnelKit.
//
//  TunnelKit is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  TunnelKit is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with TunnelKit.  If not, see <http://www.gnu.org/licenses/>.
//
//  This file incorporates work covered by the following copyright and
//  permission notice:
//
//      Copyright (c) 2018-Present Private Internet Access
//
//      Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//      The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
//      THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//
//

#import <openssl/ssl.h>
#import <openssl/err.h>
#import <openssl/evp.h>
#import <openssl/x509v3.h>

#import "TLSBox.h"
#import "Allocation.h"
#import "Errors.h"

const NSInteger TLSBoxMaxBufferLength = 16384;

NSString *const TLSBoxPeerVerificationErrorNotification = @"TLSBoxPeerVerificationErrorNotification";
//static const char *const TLSBoxClientEKU = "TLS Web Client Authentication";
static const char *const TLSBoxServerEKU = "TLS Web Server Authentication";

int TLSBoxVerifyPeer(int ok, X509_STORE_CTX *ctx) {
    if (!ok) {
        NSError *error = TunnelKitErrorWithCode(TunnelKitErrorCodeTLSBoxCA);
        [[NSNotificationCenter defaultCenter] postNotificationName:TLSBoxPeerVerificationErrorNotification
                                                            object:nil
                                                          userInfo:@{TunnelKitErrorKey: error}];
    }
    return ok;
}

@interface TLSBox ()

@property (nonatomic, strong) NSString *caPath;
@property (nonatomic, strong) NSString *clientCertificatePath;
@property (nonatomic, strong) NSString *clientKeyPath;
@property (nonatomic, assign) BOOL isConnected;

@property (nonatomic, unsafe_unretained) SSL_CTX *ctx;
@property (nonatomic, unsafe_unretained) SSL *ssl;
@property (nonatomic, unsafe_unretained) BIO *bioPlainText;
@property (nonatomic, unsafe_unretained) BIO *bioCipherTextIn;
@property (nonatomic, unsafe_unretained) BIO *bioCipherTextOut;

@property (nonatomic, unsafe_unretained) uint8_t *bufferCipherText;

@end

@implementation TLSBox

+ (NSString *)md5ForCertificatePath:(NSString *)path
{
    const EVP_MD *alg = EVP_get_digestbyname("MD5");
    uint8_t md[16];
    unsigned int len;

    FILE *pem = fopen([path cStringUsingEncoding:NSASCIIStringEncoding], "r");
    X509 *cert = PEM_read_X509(pem, NULL, NULL, NULL);
    X509_digest(cert, alg, md, &len);
    X509_free(cert);
    fclose(pem);
    NSCAssert2(len == sizeof(md), @"Unexpected MD5 size (%d != %lu)", len, sizeof(md));

    NSMutableString *hex = [[NSMutableString alloc] initWithCapacity:2 * sizeof(md)];
    for (int i = 0; i < sizeof(md); ++i) {
        [hex appendFormat:@"%02x", md[i]];
    }
    return hex;
}

- (instancetype)init
{
    [NSException raise:NSInvalidArgumentException format:@"Use initWithCAPath:clientCertificatePath:clientKeyPath:"];
    return nil;
}

- (instancetype)initWithCAPath:(NSString *)caPath clientCertificatePath:(NSString *)clientCertificatePath clientKeyPath:(NSString *)clientKeyPath
{
    if ((self = [super init])) {
        self.caPath = caPath;
        self.clientCertificatePath = clientCertificatePath;
        self.clientKeyPath = clientKeyPath;
        self.bufferCipherText = allocate_safely(TLSBoxMaxBufferLength);
    }
    return self;
}

- (void)dealloc
{
    if (!self.ctx) {
        return;
    }

    BIO_free_all(self.bioPlainText);
    SSL_free(self.ssl);
    SSL_CTX_free(self.ctx);
    self.isConnected = NO;
    self.ctx = NULL;

    bzero(self.bufferCipherText, TLSBoxMaxBufferLength);
    free(self.bufferCipherText);
}

- (BOOL)startWithError:(NSError *__autoreleasing *)error
{
    self.ctx = SSL_CTX_new(TLS_client_method());
    SSL_CTX_set_options(self.ctx, SSL_OP_NO_SSLv2 | SSL_OP_NO_SSLv3 | SSL_OP_NO_COMPRESSION);
    SSL_CTX_set_verify(self.ctx, SSL_VERIFY_PEER, TLSBoxVerifyPeer);
    if (!SSL_CTX_load_verify_locations(self.ctx, [self.caPath cStringUsingEncoding:NSASCIIStringEncoding], NULL)) {
        ERR_print_errors_fp(stdout);
        if (error) {
            *error = TunnelKitErrorWithCode(TunnelKitErrorCodeTLSBoxCA);
        }
        return NO;
    }
    
    if (self.clientCertificatePath) {
        if (!SSL_CTX_use_certificate_file(self.ctx, [self.clientCertificatePath cStringUsingEncoding:NSASCIIStringEncoding], SSL_FILETYPE_PEM)) {
            ERR_print_errors_fp(stdout);
            if (error) {
                *error = TunnelKitErrorWithCode(TunnelKitErrorCodeTLSBoxClientCertificate);
            }
            return NO;
        }

        if (self.clientKeyPath) {
            if (!SSL_CTX_use_PrivateKey_file(self.ctx, [self.clientKeyPath cStringUsingEncoding:NSASCIIStringEncoding], SSL_FILETYPE_PEM)) {
                ERR_print_errors_fp(stdout);
                if (error) {
                    *error = TunnelKitErrorWithCode(TunnelKitErrorCodeTLSBoxClientKey);
                }
                return NO;
            }
        }
    }

    self.ssl = SSL_new(self.ctx);
    
    self.bioPlainText = BIO_new(BIO_f_ssl());
    self.bioCipherTextIn  = BIO_new(BIO_s_mem());
    self.bioCipherTextOut = BIO_new(BIO_s_mem());
    
    SSL_set_connect_state(self.ssl);
    
    SSL_set_bio(self.ssl, self.bioCipherTextIn, self.bioCipherTextOut);
    BIO_set_ssl(self.bioPlainText, self.ssl, BIO_NOCLOSE);
    
    if (!SSL_do_handshake(self.ssl)) {
        if (error) {
            *error = TunnelKitErrorWithCode(TunnelKitErrorCodeTLSBoxHandshake);
        }
        return NO;
    }
    return YES;
}

#pragma mark Pull

- (NSData *)pullCipherTextWithError:(NSError *__autoreleasing *)error
{
    if (!self.isConnected && !SSL_is_init_finished(self.ssl)) {
        SSL_do_handshake(self.ssl);
    }
    const int ret = BIO_read(self.bioCipherTextOut, self.bufferCipherText, TLSBoxMaxBufferLength);
    if (!self.isConnected && SSL_is_init_finished(self.ssl)) {
        self.isConnected = YES;

        if (![self verifyEKUWithSSL:self.ssl]) {
            if (error) {
                *error = TunnelKitErrorWithCode(TunnelKitErrorCodeTLSBoxServerEKU);
            }
            return nil;
        }
    }
    if (ret > 0) {
        return [NSData dataWithBytes:self.bufferCipherText length:ret];
    }
    if ((ret < 0) && !BIO_should_retry(self.bioCipherTextOut)) {
        if (error) {
            *error = TunnelKitErrorWithCode(TunnelKitErrorCodeTLSBoxHandshake);
        }
    }
    return nil;
}

- (BOOL)pullRawPlainText:(uint8_t *)text length:(NSInteger *)length error:(NSError *__autoreleasing *)error
{
    NSParameterAssert(text);
    NSParameterAssert(length);

    const int ret = BIO_read(self.bioPlainText, text, TLSBoxMaxBufferLength);
    if (ret > 0) {
        *length = ret;
        return YES;
    }
    if ((ret < 0) && !BIO_should_retry(self.bioPlainText)) {
        if (error) {
            *error = TunnelKitErrorWithCode(TunnelKitErrorCodeTLSBoxHandshake);
        }
    }
    return NO;
}

#pragma mark Put

- (BOOL)putCipherText:(NSData *)text error:(NSError *__autoreleasing *)error
{
    NSParameterAssert(text);
    
    return [self putRawCipherText:(const uint8_t *)text.bytes length:text.length error:error];
}

- (BOOL)putRawCipherText:(const uint8_t *)text length:(NSInteger)length error:(NSError *__autoreleasing *)error
{
    NSParameterAssert(text);

    const int ret = BIO_write(self.bioCipherTextIn, text, (int)length);
    if (ret != length) {
        if (error) {
            *error = TunnelKitErrorWithCode(TunnelKitErrorCodeTLSBoxHandshake);
        }
        return NO;
    }
    return YES;
}

- (BOOL)putPlainText:(NSString *)text error:(NSError *__autoreleasing *)error
{
    NSParameterAssert(text);

    return [self putRawPlainText:(const uint8_t *)[text cStringUsingEncoding:NSASCIIStringEncoding] length:text.length error:error];
}

- (BOOL)putRawPlainText:(const uint8_t *)text length:(NSInteger)length error:(NSError *__autoreleasing *)error
{
    NSParameterAssert(text);

    const int ret = BIO_write(self.bioPlainText, text, (int)length);
    if (ret != length) {
        if (error) {
            *error = TunnelKitErrorWithCode(TunnelKitErrorCodeTLSBoxHandshake);
        }
        return NO;
    }
    return YES;
}

#pragma mark EKU

- (BOOL)verifyEKUWithSSL:(SSL *)ssl
{
    X509 *cert = SSL_get_peer_certificate(self.ssl);
    if (!cert) {
        return NO;
    }

    // don't be afraid of saving some time:
    //
    // https://stackoverflow.com/questions/37047379/how-extract-all-oids-from-certificate-with-openssl
    //
    const int extIndex = X509_get_ext_by_NID(cert, NID_ext_key_usage, -1);
    if (extIndex < 0) {
        X509_free(cert);
        return NO;
    }
    X509_EXTENSION *ext = X509_get_ext(cert, extIndex);
    if (!ext) {
        X509_free(cert);
        return NO;
    }

    EXTENDED_KEY_USAGE *eku = X509V3_EXT_d2i(ext);
    if (!eku) {
        X509_free(cert);
        return NO;
    }
    const int num = sk_ASN1_OBJECT_num(eku);
    char buffer[100];
    BOOL isValid = NO;

    for (int i = 0; i < num; ++i) {
        OBJ_obj2txt(buffer, sizeof(buffer), sk_ASN1_OBJECT_value(eku, i), 1); // get OID
        const char *oid = OBJ_nid2ln(OBJ_obj2nid(sk_ASN1_OBJECT_value(eku, i)));
//        NSLog(@"eku flag %d: %s - %s", i, buffer, oid);
        if (!strcmp(oid, TLSBoxServerEKU)) {
            isValid = YES;
            break;
        }
    }
    EXTENDED_KEY_USAGE_free(eku);
    X509_free(cert);

    return isValid;
}

@end
