//
//  MASPushService.m
//  MASFoundation
//
//  Copyright (c) 2017 CA. All rights reserved.
//
//  This software may be modified and distributed under the terms
//  of the MIT license. See the LICENSE file for details.
//

#import "MASPushService.h"

#import "MASAccessService.h"

@implementation MASPushService

static NSString *_deviceToken_ = nil;
static BOOL _autoRegistration_ = YES;


# pragma mark - Shared Service

+ (instancetype)sharedService
{
    static id sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
                  {
                      sharedInstance = [[MASPushService alloc] initProtected];
                  });
    
    return sharedInstance;
}


# pragma mark - Service Lifecycle

+ (NSString *)serviceUUID
{
    return MASPushServiceUUID;
}


- (void)serviceDidLoad
{
    
    [super serviceDidLoad];
}


- (void)serviceWillStart
{
    [super serviceWillStart];
    
    //
    // Subscribe for MAS events if auto registration is enabled
    //
    if(_autoRegistration_)
        [self registerForEvents];
}


- (void)serviceDidStart
{
    [super serviceDidStart];
}


- (void)serviceWillStop
{
    [super serviceWillStop];
    
    //
    // Unsubscribe for MAS events if auto registration is enabled
    //
    if(_autoRegistration_)
        [self unregisterForEvents];
}


- (void)serviceDidStop
{
    [super serviceDidStop];
}


- (void)serviceDidReset
{
    [super serviceDidReset];
    
}


#pragma mark - Notifications

- (void)registerForEvents
{
    NSArray* notificationNames = @[MASDidStartNotification, MASUserDidAuthenticateNotification];
    
    for (NSString* notificationName in notificationNames)
    {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notificationReceived:) name:notificationName object:nil];
    }
}

- (void)unregisterForEvents
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)notificationReceived:(NSNotification*)notification
{
    if(!self.isRegistered)
    {
        //
        // Register for Push if application is already authenticated after MAS starts
        //
        if ([notification.name isEqualToString: MASDidStartNotification]) {
            
            if([MASApplication currentApplication].isAuthenticated)
            {
                [self registerDevice:nil];
            }
        }
        
        //
        // Register for Push after user authenticates
        //
        if ([notification.name isEqualToString: MASUserDidAuthenticateNotification]) {
            if([notification.object isKindOfClass:[MASAuthCredentials class]]) //remove refresh token
            {
                [self registerDevice:nil];
            }
        }
        
        //
        // Placeholder to cover aditional user cases
        //
//        else if ([notification.name isEqualToString: MASDidSwitchGatewayServerNotification]) {
//            
//        }
//        else if ([notification.name isEqualToString: MASUserDidLogoutNotification]) {
//            
//        }
//        else if ([notification.name isEqualToString: MASDeviceDidDeregisterNotification]) {
//            
//        }
    }

}


# pragma mark - Push methods

- (void)enableAutoRegistration:(BOOL)enable
{
    _autoRegistration_ = enable;
}


- (BOOL)isKAutoRegistrationEnabled
{
    return _autoRegistration_;
}


- (BOOL)isRegistered
{
    //
    // Retrieve deviceToken from Keychain, if it was already registered should be the same
    //
    NSString *deviceTokenFromKeyChain = [[MASAccessService sharedService] getAccessValueStringWithType:MASAccessValueTypeDeviceToken];
    
    return ([_deviceToken_ isEqualToString:deviceTokenFromKeyChain] && _deviceToken_);
}


- (void)setDeviceToken:(NSString *_Nonnull)deviceToken
{
    _deviceToken_ = deviceToken;
}


- (void)clearDeviceToken
{
     [[MASAccessService sharedService] setAccessValueString:nil withAccessValueType:MASAccessValueTypeDeviceToken];
}


- (NSString *)deviceToken
{
    return _deviceToken_;
}


- (void)registerDevice:(MASCompletionErrorBlock _Nullable)completion
{
    //
    // Check if the device token was set
    //
    if(!_deviceToken_)
    {
        //
        // Notify
        //
        if(completion) completion(NO, [NSError errorForFoundationCode:(MASFoundationErrorCodePushDeviceTokenInvalid) errorDomain:MASFoundationErrorDomainLocal]);
        
        return;
    }
    
    //
    // Check if device token was already registered
    //
    if(self.isRegistered)
    {
        //
        // Notify
        //
        if(completion) completion(NO, [NSError errorForFoundationCode:(MASFoundationErrorCodePushDeviceAlreadyRegistered) errorDomain:MASFoundationErrorDomainLocal]);
        
        return;
    }
    
    //
    // Post notification the Mobile SDK will attempt to register for push
    //
    [[NSNotificationCenter defaultCenter] postNotificationName:MASPushWillRegisterNotification object:nil];
    
    //
    // Endpoint
    //
    NSString *endPoint = [MASConfiguration currentConfiguration].pushNotificationRegisterEndpoint;
    
    //
    // Headers
    //
    MASIMutableOrderedDictionary *headerInfo = [MASIMutableOrderedDictionary new];

    // Client Authorization with 'Authorization' header key
    NSString *clientAuthorization = [[MASApplication currentApplication] clientAuthorizationBasicHeaderValue];
    if(clientAuthorization) headerInfo[MASAuthorizationRequestResponseKey] = clientAuthorization;
    
    // MAG Identifier
    NSString *magIdentifier = [[MASAccessService sharedService] getAccessValueStringWithType:MASAccessValueTypeMAGIdentifier];
    if(magIdentifier) headerInfo[MASMagIdentifierRequestResponseKey] = magIdentifier;
    
    //
    // Parameters
    //
    MASIMutableOrderedDictionary *parameterInfo = [MASIMutableOrderedDictionary new];
    
    // DeviceToken
    parameterInfo[MASPushNotificationDeviceTokenRequestResponseKey] = _deviceToken_;
    
    //
    // Trigger the request
    //
    [[MASNetworkingService sharedService] postTo:endPoint
                                  withParameters:parameterInfo
                                      andHeaders:headerInfo
                                     requestType:MASRequestResponseTypeWwwFormUrlEncoded
                                    responseType:MASRequestResponseTypeJson
     //
     // Handle the response
     //
                                      completion:^(NSDictionary *responseInfo, NSError *error)
     {
         //
         // If error stop here
         //
         if(error)
         {
             NSError *apiError = [NSError errorFromApiResponseInfo:responseInfo andError:error];
             
             //
             // Notify completion block
             //
             if(completion) completion(NO, apiError);
             
             //
             // Post did fail to register for push notifications
             //
             [[NSNotificationCenter defaultCenter] postNotificationName:MASPushDidFailToRegisterNotification object:apiError];
             
             return;
         }
         
         //
         // Store the deviceToken in the keychain
         //
         else {
             [[MASAccessService sharedService] setAccessValueString:_deviceToken_ withAccessValueType:MASAccessValueTypeDeviceToken];
         }
         
         //
         // Post did register for push notification
         //
         [[NSNotificationCenter defaultCenter] postNotificationName:MASPushDidRegisterNotification object:nil];
         
         //
         // Notify
         //
         if(completion) completion(YES, nil);

     }
     ];
}


- (void)deregisterDevice:(MASCompletionErrorBlock _Nullable)completion
{
    if(!_deviceToken_)
    {
        //
        // Notify
        //
        if(completion) completion(NO, [NSError errorForFoundationCode:(MASFoundationErrorCodePushDeviceTokenInvalid) errorDomain:MASFoundationErrorDomainLocal]);
        
        return;
    }
    
    //
    // Post notification the Mobile SDK will attempt to remove device from push
    //
    [[NSNotificationCenter defaultCenter] postNotificationName:MASPushWillRemoveNotification object:nil];
    
    //
    // Endpoint
    //
    NSString *endPoint = [MASConfiguration currentConfiguration].pushNotificationRegisterEndpoint;
    
    //
    // Headers
    //
    MASIMutableOrderedDictionary *headerInfo = [MASIMutableOrderedDictionary new];
    
    // Client Authorization with 'Authorization' header key
    NSString *clientAuthorization = [[MASApplication currentApplication] clientAuthorizationBasicHeaderValue];
    if(clientAuthorization) headerInfo[MASAuthorizationRequestResponseKey] = clientAuthorization;
    
    // MAG Identifier
    NSString *magIdentifier = [[MASAccessService sharedService] getAccessValueStringWithType:MASAccessValueTypeMAGIdentifier];
    if(magIdentifier) headerInfo[MASMagIdentifierRequestResponseKey] = magIdentifier;
    
    //
    // Parameters
    //
    MASIMutableOrderedDictionary *parameterInfo = [MASIMutableOrderedDictionary new];
    
    // DeviceToken
    parameterInfo[MASPushNotificationDeviceTokenRequestResponseKey] = _deviceToken_;
    
    //
    // Trigger the request
    //
    [[MASNetworkingService sharedService] postTo:endPoint
                                  withParameters:parameterInfo
                                      andHeaders:headerInfo
                                     requestType:MASRequestResponseTypeWwwFormUrlEncoded
                                    responseType:MASRequestResponseTypeJson
     //
     // Handle the response
     //
                                      completion:^(NSDictionary *responseInfo, NSError *error)
     {
         //
         // If error stop here
         //
         if(error)
         {
             NSError *apiError = [NSError errorFromApiResponseInfo:responseInfo andError:error];
             
             //
             // Notify completion block
             //
             if(completion) completion(NO, apiError);
             
             //
             // Post did fail to remove device from push
             //
             [[NSNotificationCenter defaultCenter] postNotificationName:MASPushDidFailToRemoveNotification object:apiError];
             
             return;
         }
         
         //
         // Remove the deviceToken from keychain
         //
         else {
             [[MASAccessService sharedService] setAccessValueString:nil withAccessValueType:MASAccessValueTypeDeviceToken];
         }
         
         //
         // Post did remove the device from push notification
         //
         [[NSNotificationCenter defaultCenter] postNotificationName:MASPushDidRemoveNotification object:nil];
         
         //
         // Notify
         //
         if(completion) completion(YES, nil);
         
     }
     ];
}


@end