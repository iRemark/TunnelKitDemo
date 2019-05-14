//
//  ViewController.swift
//  TunnelKitDemo
//
//  Created by lichao on 2018/12/3.
//  Copyright © 2018 http://www.cnblogs.com/saytome/. All rights reserved.
//

import UIKit

import NetworkExtension
import TunnelKit
import Passepartout

extension ViewController {
    private static let appGroup = "group.com.shoplex.vpn.pandavpn"
    private static let bundleIdentifier = "com.shoplex.pandavpn.newtunnel"
    
    private static let account = "BD11EB4A-A28C-493D-AF13-6FB37967E9D6"
    private static let password = "905fed54114d9143df189c511fe5eaf38269"
    private static let ovpnUrl = "https://d3copiidm24d6d.cloudfront.net/open-vpn/HeNvKMPGBgsSQGHz.ovpn"
    
    private func url(withName name: String) -> URL {
        return Bundle(for: ViewController.self).url(forResource: name, withExtension: "ovpn")!
    }
    
    
    private func makeProtocol() -> NETunnelProviderProtocol {
        
        let credentials = SessionProxy.Credentials(ViewController.account, ViewController.password);
        let parsedFile = try? TunnelKitProvider.Configuration.parsed(fromURL: URL(string: ViewController.ovpnUrl)!);
        
        let sessionConfig = parsedFile?.configuration.sessionConfiguration;
        var builder = TunnelKitProvider.ConfigurationBuilder(sessionConfiguration: sessionConfig!)
        if let endpointProtocols = parsedFile?.configuration.endpointProtocols {
            builder.endpointProtocols = endpointProtocols
        }
        builder.shouldDebug = true
        
        let configuration = builder.build()
        let hostname = parsedFile?.hostname;
        
        return try! configuration.generatedTunnelProtocol(
            withBundleIdentifier: ViewController.bundleIdentifier,
            appGroup: ViewController.appGroup,
            hostname: hostname ?? "",
            credentials: credentials
        )
    }
}




class ViewController: UIViewController, URLSessionDataDelegate {
    var currentManager: NETunnelProviderManager?
    
    var status = NEVPNStatus.invalid
    let buttonConnection =  UIButton.init(type: .custom);
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = UIColor.white;
        
        buttonConnection.frame = CGRect.init(x: 0, y: 200, width: UIScreen.main.bounds.size.width, height: 80);
        buttonConnection.backgroundColor = UIColor.red;
        buttonConnection.addTarget(self, action: #selector(connectionClicked(_:)), for: .touchUpInside);
        buttonConnection.setTitle("tap", for: .normal);
        self.view.addSubview(buttonConnection);
        
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(VPNStatusDidChange(notification:)),
                                               name: .NEVPNStatusDidChange,
                                               object: nil)
        
        reloadCurrentManager(nil)
    }
    
    @objc func connectionClicked(_ sender: Any) {
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
            reloadCurrentManager({ (error) in
                block()
            })
        }
        else {
            block()
        }
    }
    
    
    
    func connect() {
        configureVPN({ (manager) in
            return self.makeProtocol()
        }, completionHandler: { (error) in
            if let error = error {
                print("configure error: \(error)")
                return
            }
            let session = self.currentManager?.connection as! NETunnelProviderSession
            do {
                try session.startTunnel()
            } catch let e {
                print("error starting tunnel: \(e)")
            }
        })
    }
    
    func disconnect() {
        configureVPN({ (manager) in
            return nil
        }, completionHandler: { (error) in
            self.currentManager?.connection.stopVPNTunnel()
        })
    }
    
    func displayLog() {
        guard let vpn = currentManager?.connection as? NETunnelProviderSession else {
            return
        }
        try? vpn.sendProviderMessage(TunnelKitProvider.Message.requestLog.data) { (data) in
            guard let log = String(data: data!, encoding: .utf8) else {
                return
            }
            
            
            print("💖 \(log)");
        }
    }
    
    func configureVPN(_ configure: @escaping (NETunnelProviderManager) -> NETunnelProviderProtocol?, completionHandler: @escaping (Error?) -> Void) {
        reloadCurrentManager { (error) in
            if let error = error {
                print("error reloading preferences: \(error)")
                completionHandler(error)
                return
            }
            
            let manager = self.currentManager!
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
                self.reloadCurrentManager(completionHandler)
            }
        }
    }
    
    func reloadCurrentManager(_ completionHandler: ((Error?) -> Void)?) {
        NETunnelProviderManager.loadAllFromPreferences { (managers, error) in
            if let error = error {
                completionHandler?(error)
                return
            }
            
            var manager: NETunnelProviderManager?
            
            for m in managers! {
                if let p = m.protocolConfiguration as? NETunnelProviderProtocol {
                    if (p.providerBundleIdentifier == ViewController.bundleIdentifier) {
                        manager = m
                        break
                    }
                }
            }
            
            if (manager == nil) {
                manager = NETunnelProviderManager()
            }
            
            self.currentManager = manager
            self.status = manager!.connection.status
            self.updateButton()
            completionHandler?(nil)
        }
    }
    
    func updateButton() {
        switch status {
        case .connected :
            buttonConnection.setTitle("connected", for: .normal)
            
        case .connecting:
            buttonConnection.setTitle("connecting", for: .normal)
            
        case .disconnected:
            buttonConnection.setTitle("disconnected", for: .normal)
            
        case .disconnecting:
            buttonConnection.setTitle("disconnecting", for: .normal)
            
        default:
            break
        }
    }
    
    @objc private func VPNStatusDidChange(notification: NSNotification) {
        guard let status = currentManager?.connection.status else {
            print("VPNStatusDidChange")
            return
        }
        print("VPNStatusDidChange: \(status.rawValue)")
        self.status = status
        updateButton()
    }
    
}


