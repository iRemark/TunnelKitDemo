//
//  TunnelKitProvider+Configuration.swift
//  TunnelKit
//
//  Created by Davide De Rosa on 10/23/17.
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

import Foundation
import NetworkExtension
import SwiftyBeaver

private let log = SwiftyBeaver.self

extension TunnelKitProvider {

    // MARK: Configuration
    
    /// A socket type between UDP (recommended) and TCP.
    public enum SocketType: String {

        /// UDP socket type.
        case udp = "UDP"
        
        /// TCP socket type.
        case tcp = "TCP"
    }
    
    /// Defines the communication protocol of an endpoint.
    public struct EndpointProtocol: RawRepresentable, Equatable, CustomStringConvertible {

        /// The socket type.
        public let socketType: SocketType
        
        /// The remote port.
        public let port: UInt16
        
        /// :nodoc:
        public init(_ socketType: SocketType, _ port: UInt16) {
            self.socketType = socketType
            self.port = port
        }
        
        // MARK: RawRepresentable
        
        /// :nodoc:
        public init?(rawValue: String) {
            let components = rawValue.components(separatedBy: ":")
            guard components.count == 2 else {
                return nil
            }
            guard let socketType = SocketType(rawValue: components[0]) else {
                return nil
            }
            guard let port = UInt16(components[1]) else {
                return nil
            }
            self.init(socketType, port)
        }
        
        /// :nodoc:
        public var rawValue: String {
            return "\(socketType.rawValue):\(port)"
        }

        // MARK: Equatable
        
        /// :nodoc:
        public static func ==(lhs: EndpointProtocol, rhs: EndpointProtocol) -> Bool {
            return (lhs.socketType == rhs.socketType) && (lhs.port == rhs.port)
        }
        
        // MARK: CustomStringConvertible
        
        /// :nodoc:
        public var description: String {
            return rawValue
        }
    }

    /// The way to create a `TunnelKitProvider.Configuration` object for the tunnel profile.
    public struct ConfigurationBuilder {

        /// :nodoc:
        public static let defaults = Configuration(
            prefersResolvedAddresses: false,
            resolvedAddresses: nil,
            endpointProtocols: [EndpointProtocol(.udp, 1194)],
            mtu: 1250,
            sessionConfiguration: SessionProxy.Configuration(
                cipher: .aes128cbc,
                digest: .sha1,
                ca: CryptoContainer(pem: ""),
                clientCertificate: nil,
                clientKey: nil,
                compressionFraming: .disabled,
                tlsWrap: nil,
                keepAliveInterval: nil,
                renegotiatesAfter: nil,
                usesPIAPatches: nil
            ),
            shouldDebug: false,
            debugLogKey: nil,
            debugLogFormat: nil,
            lastErrorKey: nil
        )
        
        /// Prefers resolved addresses over DNS resolution. `resolvedAddresses` must be set and non-empty. Default is `false`.
        ///
        /// - Seealso: `fallbackServerAddresses`
        public var prefersResolvedAddresses: Bool
        
        /// Resolved addresses in case DNS fails or `prefersResolvedAddresses` is `true`.
        public var resolvedAddresses: [String]?
        
        /// The accepted communication protocols. Must be non-empty.
        public var endpointProtocols: [EndpointProtocol]

        /// The MTU of the link.
        public var mtu: Int
        
        /// The session configuration.
        public var sessionConfiguration: SessionProxy.Configuration
        
        // MARK: Debugging
        
        /// Enables debugging.
        public var shouldDebug: Bool
        
        /// This attribute is ignored and deprecated. Use `urlForLog(...)` or `existingLog(...)` to access the debug log.
        @available(*, deprecated)
        public var debugLogKey: String?
        
        /// Optional debug log format (SwiftyBeaver format).
        public var debugLogFormat: String?
        
        /// This attribute is ignored and deprecated. Use `lastError(...)` to access the last error.
        @available(*, deprecated)
        public var lastErrorKey: String?
        
        // MARK: Building
        
        /**
         Default initializer.
         
         - Parameter ca: The CA certificate.
         */
        public init(sessionConfiguration: SessionProxy.Configuration) {
            prefersResolvedAddresses = ConfigurationBuilder.defaults.prefersResolvedAddresses
            resolvedAddresses = nil
            endpointProtocols = ConfigurationBuilder.defaults.endpointProtocols
            mtu = ConfigurationBuilder.defaults.mtu
            self.sessionConfiguration = sessionConfiguration
            shouldDebug = ConfigurationBuilder.defaults.shouldDebug
            debugLogFormat = ConfigurationBuilder.defaults.debugLogFormat
        }
        
        fileprivate init(providerConfiguration: [String: Any]) throws {
            let S = Configuration.Keys.self

            prefersResolvedAddresses = providerConfiguration[S.prefersResolvedAddresses] as? Bool ?? ConfigurationBuilder.defaults.prefersResolvedAddresses
            resolvedAddresses = providerConfiguration[S.resolvedAddresses] as? [String]
            guard let endpointProtocolsStrings = providerConfiguration[S.endpointProtocols] as? [String], !endpointProtocolsStrings.isEmpty else {
                throw ProviderConfigurationError.parameter(name: "protocolConfiguration.providerConfiguration[\(S.endpointProtocols)] is nil or empty")
            }
            endpointProtocols = try endpointProtocolsStrings.map {
                guard let ep = EndpointProtocol(rawValue: $0) else {
                    throw ProviderConfigurationError.parameter(name: "protocolConfiguration.providerConfiguration[\(S.endpointProtocols)] has a badly formed element")
                }
                return ep
            }
            mtu = providerConfiguration[S.mtu] as? Int ?? ConfigurationBuilder.defaults.mtu
            
            //

            guard let cipherAlgorithm = providerConfiguration[S.cipherAlgorithm] as? String, let cipher = SessionProxy.Cipher(rawValue: cipherAlgorithm) else {
                throw ProviderConfigurationError.parameter(name: "protocolConfiguration.providerConfiguration[\(S.cipherAlgorithm)]")
            }
            guard let digestAlgorithm = providerConfiguration[S.digestAlgorithm] as? String, let digest = SessionProxy.Digest(rawValue: digestAlgorithm) else {
                throw ProviderConfigurationError.parameter(name: "protocolConfiguration.providerConfiguration[\(S.digestAlgorithm)]")
            }

            let ca: CryptoContainer
            let clientCertificate: CryptoContainer?
            let clientKey: CryptoContainer?
            guard let caPEM = providerConfiguration[S.ca] as? String else {
                throw ProviderConfigurationError.parameter(name: "protocolConfiguration.providerConfiguration[\(S.ca)]")
            }
            ca = CryptoContainer(pem: caPEM)
            if let clientPEM = providerConfiguration[S.clientCertificate] as? String {
                guard let keyPEM = providerConfiguration[S.clientKey] as? String else {
                    throw ProviderConfigurationError.parameter(name: "protocolConfiguration.providerConfiguration[\(S.clientKey)]")
                }

                clientCertificate = CryptoContainer(pem: clientPEM)
                clientKey = CryptoContainer(pem: keyPEM)
            } else {
                clientCertificate = nil
                clientKey = nil
            }

            var sessionConfigurationBuilder = SessionProxy.ConfigurationBuilder(ca: ca)
            sessionConfigurationBuilder.cipher = cipher
            sessionConfigurationBuilder.digest = digest
            sessionConfigurationBuilder.clientCertificate = clientCertificate
            sessionConfigurationBuilder.clientKey = clientKey
            if let compressionFramingValue = providerConfiguration[S.compressionFraming] as? Int, let compressionFraming = SessionProxy.CompressionFraming(rawValue: compressionFramingValue) {
                sessionConfigurationBuilder.compressionFraming = compressionFraming
            } else {
                sessionConfigurationBuilder.compressionFraming = ConfigurationBuilder.defaults.sessionConfiguration.compressionFraming
            }
            if let tlsWrapData = providerConfiguration[S.tlsWrap] as? Data {
                do {
                    sessionConfigurationBuilder.tlsWrap = try SessionProxy.TLSWrap.deserialized(tlsWrapData)
                } catch {
                    throw ProviderConfigurationError.parameter(name: "protocolConfiguration.providerConfiguration[\(S.tlsWrap)]")
                }
            }
            sessionConfigurationBuilder.keepAliveInterval = providerConfiguration[S.keepAlive] as? TimeInterval
            sessionConfigurationBuilder.renegotiatesAfter = providerConfiguration[S.renegotiatesAfter] as? TimeInterval
            sessionConfigurationBuilder.usesPIAPatches = providerConfiguration[S.usesPIAPatches] as? Bool ?? false
            sessionConfiguration = sessionConfigurationBuilder.build()

            shouldDebug = providerConfiguration[S.debug] as? Bool ?? false
            if shouldDebug {
                debugLogFormat = providerConfiguration[S.debugLogFormat] as? String
            }

            guard !prefersResolvedAddresses || !(resolvedAddresses?.isEmpty ?? true) else {
                throw ProviderConfigurationError.parameter(name: "protocolConfiguration.providerConfiguration[\(S.prefersResolvedAddresses)] is true but no [\(S.resolvedAddresses)]")
            }
        }
        
        /**
         Builds a `TunnelKitProvider.Configuration` object that will connect to the provided endpoint.
         
         - Returns: A `TunnelKitProvider.Configuration` object with this builder and the additional method parameters.
         */
        public func build() -> Configuration {
            return Configuration(
                prefersResolvedAddresses: prefersResolvedAddresses,
                resolvedAddresses: resolvedAddresses,
                endpointProtocols: endpointProtocols,
                mtu: mtu,
                sessionConfiguration: sessionConfiguration,
                shouldDebug: shouldDebug,
                debugLogKey: nil,
                debugLogFormat: shouldDebug ? debugLogFormat : nil,
                lastErrorKey: nil
            )
        }
    }
    
    /// Offers a bridge between the abstract `TunnelKitProvider.ConfigurationBuilder` and a concrete `NETunnelProviderProtocol` profile.
    public struct Configuration: Codable {
        struct Keys {
            static let appGroup = "AppGroup"
            
            static let prefersResolvedAddresses = "PrefersResolvedAddresses"

            static let resolvedAddresses = "ResolvedAddresses"

            static let endpointProtocols = "EndpointProtocols"
            
            static let mtu = "MTU"
            
            // MARK: SessionConfiguration

            static let cipherAlgorithm = "CipherAlgorithm"
            
            static let digestAlgorithm = "DigestAlgorithm"
            
            static let ca = "CA"
            
            static let clientCertificate = "ClientCertificate"
            
            static let clientKey = "ClientKey"
            
            static let compressionFraming = "CompressionFraming"
            
            static let tlsWrap = "TLSWrap"

            static let keepAlive = "KeepAlive"
            
            static let renegotiatesAfter = "RenegotiatesAfter"
            
            static let usesPIAPatches = "UsesPIAPatches"

            // MARK: Debugging
            
            static let debug = "Debug"
            
            static let debugLogFormat = "DebugLogFormat"
        }
        
        /// - Seealso: `TunnelKitProvider.ConfigurationBuilder.prefersResolvedAddresses`
        public let prefersResolvedAddresses: Bool
        
        /// - Seealso: `TunnelKitProvider.ConfigurationBuilder.resolvedAddresses`
        public let resolvedAddresses: [String]?

        /// - Seealso: `TunnelKitProvider.ConfigurationBuilder.endpointProtocols`
        public let endpointProtocols: [EndpointProtocol]
        
        /// - Seealso: `TunnelKitProvider.ConfigurationBuilder.mtu`
        public let mtu: Int
        
        /// - Seealso: `TunnelKitProvider.ConfigurationBuilder.sessionConfiguration`
        public let sessionConfiguration: SessionProxy.Configuration
        
        /// - Seealso: `TunnelKitProvider.ConfigurationBuilder.shouldDebug`
        public let shouldDebug: Bool
        
        /// - Seealso: `TunnelKitProvider.ConfigurationBuilder.debugLogKey`
        @available(*, deprecated)
        public let debugLogKey: String?
        
        /// - Seealso: `TunnelKitProvider.ConfigurationBuilder.debugLogFormat`
        public let debugLogFormat: String?
        
        /// - Seealso: `TunnelKitProvider.ConfigurationBuilder.lastErrorKey`
        @available(*, deprecated)
        public let lastErrorKey: String?
        
        // MARK: Shortcuts

        static let debugLogFilename = "debug.log"

        static let lastErrorKey = "LastTunnelKitError"
        
        /**
         Returns the URL of the latest debug log.

         - Parameter in: The app group where to locate the log file.
         - Returns: The URL of the debug log, if any.
         */
        public func urlForLog(in appGroup: String) -> URL? {
            guard shouldDebug else {
                return nil
            }
            guard let parentURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
                return nil
            }
            return parentURL.appendingPathComponent(Configuration.debugLogFilename)
        }

        /**
         Returns the content of the latest debug log.
         
         - Parameter in: The app group where to locate the log file.
         - Returns: The content of the debug log, if any.
         */
        public func existingLog(in appGroup: String) -> String? {
            guard let url = urlForLog(in: appGroup) else {
                return nil
            }
            return try? String(contentsOf: url)
        }
        
        /**
         Returns the last error reported by the tunnel, if any.
         
         - Parameter in: The app group where to locate the error key.
         - Returns: The last tunnel error, if any.
         */
        public func lastError(in appGroup: String) -> ProviderError? {
            guard let rawValue = UserDefaults(suiteName: appGroup)?.string(forKey: Configuration.lastErrorKey) else {
                return nil
            }
            return ProviderError(rawValue: rawValue)
        }

        /**
         Clear the last error status.
         
         - Parameter in: The app group where to locate the error key.
         */
        public func clearLastError(in appGroup: String) {
            UserDefaults(suiteName: appGroup)?.removeObject(forKey: Configuration.lastErrorKey)
        }
        
        // MARK: API
        
        /**
         Parses the app group from a provider configuration map.
         
         - Parameter from: The map to parse.
         - Returns: The parsed app group.
         - Throws: `ProviderError.configuration` if `providerConfiguration` does not contain an app group.
         */
        public static func appGroup(from providerConfiguration: [String: Any]) throws -> String {
            guard let appGroup = providerConfiguration[Keys.appGroup] as? String else {
                throw ProviderConfigurationError.parameter(name: "protocolConfiguration.providerConfiguration[\(Keys.appGroup)]")
            }
            return appGroup
        }
        
        /**
         Parses a new `TunnelKitProvider.Configuration` object from a provider configuration map.
         
         - Parameter from: The map to parse.
         - Returns: The parsed `TunnelKitProvider.Configuration` object.
         - Throws: `ProviderError.configuration` if `providerConfiguration` is incomplete.
         */
        public static func parsed(from providerConfiguration: [String: Any]) throws -> Configuration {
            let builder = try ConfigurationBuilder(providerConfiguration: providerConfiguration)
            return builder.build()
        }
        
        /**
         Returns a dictionary representation of this configuration for use with `NETunnelProviderProtocol.providerConfiguration`.

         - Parameter appGroup: The name of the app group in which the tunnel extension lives in.
         - Returns: The dictionary representation of `self`.
         */
        public func generatedProviderConfiguration(appGroup: String) -> [String: Any] {
            let S = Keys.self
            
            var dict: [String: Any] = [
                S.appGroup: appGroup,
                S.prefersResolvedAddresses: prefersResolvedAddresses,
                S.endpointProtocols: endpointProtocols.map { $0.rawValue },
                S.cipherAlgorithm: sessionConfiguration.cipher.rawValue,
                S.digestAlgorithm: sessionConfiguration.digest.rawValue,
                S.ca: sessionConfiguration.ca.pem,
                S.mtu: mtu,
                S.debug: shouldDebug
            ]
            if let clientCertificate = sessionConfiguration.clientCertificate {
                dict[S.clientCertificate] = clientCertificate.pem
            }
            if let clientKey = sessionConfiguration.clientKey {
                dict[S.clientKey] = clientKey.pem
            }
            if let resolvedAddresses = resolvedAddresses {
                dict[S.resolvedAddresses] = resolvedAddresses
            }
            dict[S.compressionFraming] = sessionConfiguration.compressionFraming.rawValue
            if let tlsWrapData = sessionConfiguration.tlsWrap?.serialized() {
                dict[S.tlsWrap] = tlsWrapData
            }
            if let keepAliveSeconds = sessionConfiguration.keepAliveInterval {
                dict[S.keepAlive] = keepAliveSeconds
            }
            if let renegotiatesAfterSeconds = sessionConfiguration.renegotiatesAfter {
                dict[S.renegotiatesAfter] = renegotiatesAfterSeconds
            }
            if let usesPIAPatches = sessionConfiguration.usesPIAPatches {
                dict[S.usesPIAPatches] = usesPIAPatches
            }
            if let debugLogFormat = debugLogFormat {
                dict[S.debugLogFormat] = debugLogFormat
            }
            return dict
        }
        
        /**
         Generates a `NETunnelProviderProtocol` from this configuration.
         
         - Parameter bundleIdentifier: The provider bundle identifier required to locate the tunnel extension.
         - Parameter appGroup: The name of the app group in which the tunnel extension lives in.
         - Parameter hostname: The hostname the tunnel will connect to.
         - Parameter credentials: The optional credentials to authenticate with.
         - Returns: The generated `NETunnelProviderProtocol` object.
         - Throws: `ProviderError.credentials` if unable to store `credentials.password` to the `appGroup` keychain.
         */
        public func generatedTunnelProtocol(withBundleIdentifier bundleIdentifier: String, appGroup: String, hostname: String, credentials: SessionProxy.Credentials? = nil) throws -> NETunnelProviderProtocol {
            let protocolConfiguration = NETunnelProviderProtocol()
            
            protocolConfiguration.providerBundleIdentifier = bundleIdentifier
            protocolConfiguration.serverAddress = hostname
            if let username = credentials?.username, let password = credentials?.password {
                let keychain = Keychain(group: appGroup)
                do {
                    try keychain.set(password: password, for: username, label: Bundle.main.bundleIdentifier)
                } catch _ {
                    throw ProviderConfigurationError.credentials(details: "keychain.set()")
                }
                protocolConfiguration.username = username
                protocolConfiguration.passwordReference = try? keychain.passwordReference(for: username)
            }
            protocolConfiguration.providerConfiguration = generatedProviderConfiguration(appGroup: appGroup)
            
            return protocolConfiguration
        }
        
        func print(appVersion: String?) {
            if let appVersion = appVersion {
                log.info("App version: \(appVersion)")
            }
            
            log.info("\tProtocols: \(endpointProtocols)")
            log.info("\tCipher: \(sessionConfiguration.cipher)")
            log.info("\tDigest: \(sessionConfiguration.digest)")
            if let _ = sessionConfiguration.clientCertificate {
                log.info("\tClient verification: enabled")
            } else {
                log.info("\tClient verification: disabled")
            }
            log.info("\tMTU: \(mtu)")
            log.info("\tCompression framing: \(sessionConfiguration.compressionFraming)")
            if let keepAliveSeconds = sessionConfiguration.keepAliveInterval, keepAliveSeconds > 0 {
                log.info("\tKeep-alive: \(keepAliveSeconds) seconds")
            } else {
                log.info("\tKeep-alive: never")
            }
            if let renegotiatesAfterSeconds = sessionConfiguration.renegotiatesAfter, renegotiatesAfterSeconds > 0 {
                log.info("\tRenegotiation: \(renegotiatesAfterSeconds) seconds")
            } else {
                log.info("\tRenegotiation: never")
            }
            if let tlsWrap = sessionConfiguration.tlsWrap {
                log.info("\tTLS wrapping: \(tlsWrap.strategy)")
            } else {
                log.info("\tTLS wrapping: disabled")
            }
            log.info("\tDebug: \(shouldDebug)")
        }
    }
}

// MARK: Modification

extension TunnelKitProvider.Configuration: Equatable {

    /**
     Returns a `TunnelKitProvider.ConfigurationBuilder` to use this configuration as a starting point for a new one.

     - Returns: An editable `TunnelKitProvider.ConfigurationBuilder` initialized with this configuration.
     */
    public func builder() -> TunnelKitProvider.ConfigurationBuilder {
        var builder = TunnelKitProvider.ConfigurationBuilder(sessionConfiguration: sessionConfiguration)
        builder.endpointProtocols = endpointProtocols
        builder.mtu = mtu
        builder.shouldDebug = shouldDebug
        builder.debugLogFormat = debugLogFormat
        return builder
    }

    /// :nodoc:
    public static func ==(lhs: TunnelKitProvider.Configuration, rhs: TunnelKitProvider.Configuration) -> Bool {
        return (
            (lhs.endpointProtocols == rhs.endpointProtocols) &&
            (lhs.mtu == rhs.mtu) &&
            (lhs.sessionConfiguration == rhs.sessionConfiguration)
            // XXX: tlsWrap not copied
        )
    }
}

/// :nodoc:
extension TunnelKitProvider.EndpointProtocol: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let proto = try TunnelKitProvider.EndpointProtocol(rawValue: container.decode(String.self)) else {
            throw TunnelKitProvider.ProviderConfigurationError.parameter(name: "endpointProtocol.decodable")
        }
        self.init(proto.socketType, proto.port)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
