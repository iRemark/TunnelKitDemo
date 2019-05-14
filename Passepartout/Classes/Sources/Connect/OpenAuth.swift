//
//  OpenAuthentication.swift
//  BasicTunnel-iOS
//
//  Created by Thor on 2018/12/5.
//  Copyright © 2018 Davide De Rosa. All rights reserved.
//



public class OpenAuthentication: OpenAuthenticationType {
    
    public var startTunnelOptions: [String : Any]?
    
    public var bundleIdentifier: String;
    
    public var appGroup: String;
    
    public var username: String;
    
    public var password: String;
    
    public var ovpnFileAddress: String;
    
    
    public init(bundleIdentifier: String,
         appGroup: String,
         
         username: String,
         password: String,
         ovpnFileAddress: String,
         startTunnelOptions: [String : Any]? = nil) {
        
        self.bundleIdentifier = bundleIdentifier;
        self.appGroup = appGroup;
        self.username = username;
        self.password = password;
        self.ovpnFileAddress = ovpnFileAddress;
        self.startTunnelOptions = startTunnelOptions;
    }
}
