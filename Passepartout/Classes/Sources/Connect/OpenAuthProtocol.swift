//
//  OpenAuthProtocol.swift
//  Alamofire
//
//  Created by Thor on 2018/12/29.
//

public protocol OpenAuthenticationType {
    
    /// bundle ID of tunnel eg: `com.shoplex.pandavpn.newtunnel`
    var bundleIdentifier: String { get }
    
    /// appGroup of share key chain from apple development plantform eg: "group.com.xxxx"
    var appGroup: String { get }
    
    /// Provide a username for connect
    var username: String { get }
    
    /// Provide a password for connect
    var password: String { get }
    
    /// The url address of `.ovpn` file
    var ovpnFileAddress: String { get }
    
    var startTunnelOptions: [String : Any]? { get }
    
}

