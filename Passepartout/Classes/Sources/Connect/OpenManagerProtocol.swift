//
//  OpenManager+Protocol.swift
//  BasicTunnel-iOS
//
//  Created by Thor on 2018/12/5.
//  Copyright © 2018 Davide De Rosa. All rights reserved.
//


import NetworkExtension


public protocol OpenManagerProtocol: class {
    /// The status when vpn connect.
    func connectStatusDidChange(status: NEVPNStatus);
}


extension OpenManagerProtocol {
    func connectStatusDidChange(status: NEVPNStatus) {}
}

