//
//  OpenManager.swift
//  BasicTunnel-macOS
//
//  Created by Thor on 2018/12/4.
//  Copyright © 2018 Davide De Rosa. All rights reserved.
//


import NetworkExtension
import TunnelKit



public class OpenManager<T: OpenAuthenticationType>: NSObject {
    public weak var delegate: OpenManagerProtocol?
    public var status = NEVPNStatus.invalid
    
    private var tunnelProviderManager: NETunnelProviderManager?

    private var authentication: T?
 
    public override init() {
        super.init();
        
        NotificationCenter.default.addObserver(self, selector: #selector(VPNStatusDidChange(notification:)),
                                                name: .NEVPNStatusDidChange, object: nil)
        
        reloadTunnelProviderManager(nil)
        testFetchRef()
    }
    
 
    
    @objc private func VPNStatusDidChange(notification: NSNotification) {
        guard let status = tunnelProviderManager?.connection.status else {
            print("VPNStatusDidChange error !!")
            return
        }
        print("VPNStatusDidChange: \(status.rawValue)")
        
        self.status = status
        self.delegate?.connectStatusDidChange(status: self.status);
    }
    
    public func startConnect(auth: T) {
        self.authentication = auth;
        
        let block = {
            switch (self.status) {
            case .invalid, .disconnected:
                self.connect()
                
            case .connected, .connecting:
                self.disconnect()
                
            default:
                break
            }
        }
        
        if (status == .invalid) {
            reloadTunnelProviderManager({ (error) in
                block()
            })
        }else {
            block()
        }
    }
    
    public func startDisconnect() {
        let block = {
            switch (self.status) {
            case .connected, .connecting:
                self.disconnect()
                
            default:
                break
            }
        }
        if (status == .invalid) {
            reloadTunnelProviderManager({ (error) in
                block()
            })
        }else {
            block()
        }
    }

    private func configureVPN(_ configure: @escaping (NETunnelProviderManager) -> NETunnelProviderProtocol?, completionHandler: @escaping (Error?) -> Void) {
        reloadTunnelProviderManager { (error) in
            if let error = error {
                print("error reloading preferences: \(error)")
                completionHandler(error)
                return
            }
            
            let manager = self.tunnelProviderManager!
            if let protocolConfiguration = configure(manager) {
                manager.protocolConfiguration = protocolConfiguration
            }
            manager.isEnabled = true
            
            manager.saveToPreferences { (error) in
                if let error = error {
                    print("error saving preferences: \(error)")
                    completionHandler(error)
                    return
                }
                print("saved preferences")
                self.reloadTunnelProviderManager(completionHandler)
            }
        }
    }
    
   
    private func connect()  {
        configureVPN({ (manager) in
            return self.makeProtocol()
            
        }, completionHandler: { (error) in
            if let error = error {
                print("configure error: \(error)")
                return
            }
            let session = self.tunnelProviderManager?.connection as! NETunnelProviderSession
            do {
                try session.startTunnel(options: self.authentication?.startTunnelOptions)
                
            } catch let e {
                print("error starting tunnel: \(e)")
            }
        })
    }
    
    private func disconnect() {
        configureVPN({ (manager) in
            return nil
        }, completionHandler: { (error) in
            self.tunnelProviderManager?.connection.stopVPNTunnel()
        })
    }
    
    
    private func reloadTunnelProviderManager(_ completionHandler: ((Error?) -> Void)?) {
        NETunnelProviderManager.loadAllFromPreferences { (managers, error) in
            if let error = error {
                completionHandler?(error)
                return
            }
            
            var manager: NETunnelProviderManager?
            
            for m in managers! {
                if let p = m.protocolConfiguration as? NETunnelProviderProtocol {
                    
                    if let auth = self.authentication?.bundleIdentifier, auth == p.providerBundleIdentifier {
                        manager = m
                        break
                    }
                }
            }
            
            if (manager == nil) {
                manager = NETunnelProviderManager()
            }
            
            self.tunnelProviderManager = manager
            self.status = manager!.connection.status
            completionHandler?(nil)
        }
    }

    
    private func testFetchRef() {
        //        let keychain = Keychain(group: ViewController.APP_GROUP)
        //        let username = "foo"
        //        let password = "bar"
        //
        //        guard let _ = try? keychain.set(password: password, for: username) else {
        //            print("Couldn't set password")
        //            return
        //        }
        //        guard let passwordReference = try? keychain.passwordReference(for: username) else {
        //            print("Couldn't get password reference")
        //            return
        //        }
        //        guard let fetchedPassword = try? Keychain.password(for: username, reference: passwordReference) else {
        //            print("Couldn't fetch password")
        //            return
        //        }
        //
        //        print("\(username) -> \(password)")
        //        print("\(username) -> \(fetchedPassword)")
    }
}




extension OpenManager {
    private func url(withName name: String) -> URL {
        return Bundle(for: OpenManager.self).url(forResource: name, withExtension: "ovpn")!
    }
    
    private func makeProtocol() -> NETunnelProviderProtocol? {
        guard let auth = authentication else {
            return nil;
        }
        
        print("\n\n\n\(auth.username) \n\(auth.password) \n\(auth.ovpnFileAddress) \n\n\n");
        
        let credentials = SessionProxy.Credentials(auth.username, auth.password);
        let parsedFile = try? TunnelKitProvider.Configuration.parsed(fromURL: URL(string: auth.ovpnFileAddress)!)
        
        let sessionConfig = parsedFile?.configuration.sessionConfiguration;
        var builder = TunnelKitProvider.ConfigurationBuilder(sessionConfiguration: sessionConfig!)
        if let endpointProtocols = parsedFile?.configuration.endpointProtocols {
            builder.endpointProtocols = endpointProtocols
        }
        builder.shouldDebug = true
//        builder.debugLogKey = "Log"
        
        let configuration = builder.build()
        let hostname = parsedFile?.hostname;
        
        return try! configuration.generatedTunnelProtocol(
            withBundleIdentifier: auth.bundleIdentifier,
            appGroup: auth.appGroup,
            hostname: hostname ?? "",
            credentials: credentials
        )
    }
}
