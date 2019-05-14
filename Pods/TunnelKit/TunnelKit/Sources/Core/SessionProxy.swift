//
//  SessionProxy.swift
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

import Foundation
import SwiftyBeaver
import __TunnelKitNative

private let log = SwiftyBeaver.self

/// Observes major events notified by a `SessionProxy`.
public protocol SessionProxyDelegate: class {

    /**
     Called after starting a session.

     - Parameter remoteAddress: The address of the VPN server.
     - Parameter reply: The compound `SessionReply` containing tunnel settings.
     */
    func sessionDidStart(_: SessionProxy, remoteAddress: String, reply: SessionReply)
    
    /**
     Called after stopping a session.
     
     - Parameter shouldReconnect: When `true`, the session can/should be restarted. Usually because the stop reason was recoverable.
     - Seealso: `SessionProxy.reconnect(...)`
     */
    func sessionDidStop(_: SessionProxy, shouldReconnect: Bool)
}

/// Provides methods to set up and maintain an OpenVPN session.
public class SessionProxy {
    private enum StopMethod {
        case shutdown
        
        case reconnect
    }
    
    private struct Caches {
        static let ca = "ca.pem"

        static let clientCertificate = "cert.pem"

        static let clientKey = "key.pem"
    }
    
    // MARK: Configuration
    
    private let configuration: Configuration
    
    /// The optional credentials.
    public var credentials: Credentials?
    
    private var keepAliveInterval: TimeInterval? {
        let interval: TimeInterval?
        if let negInterval = pushReply?.ping, negInterval > 0 {
            interval = TimeInterval(negInterval)
        } else if let cfgInterval = configuration.keepAliveInterval, cfgInterval > 0.0 {
            interval = cfgInterval
        } else {
            return nil
        }
        return interval
    }
    
    /// An optional `SessionProxyDelegate` for receiving session events.
    public weak var delegate: SessionProxyDelegate?
    
    // MARK: State

    private let queue: DispatchQueue

    private var tlsObserver: NSObjectProtocol?

    private var keys: [UInt8: SessionKey]

    private var oldKeys: [SessionKey]

    private var negotiationKeyIdx: UInt8
    
    private var currentKeyIdx: UInt8?
    
    private var negotiationKey: SessionKey {
        guard let key = keys[negotiationKeyIdx] else {
            fatalError("Keys are empty or index \(negotiationKeyIdx) not found in \(keys.keys)")
        }
        return key
    }
    
    private var currentKey: SessionKey? {
        guard let i = currentKeyIdx else {
            return nil
        }
        return keys[i]
    }
    
    private var link: LinkInterface?
    
    private var tunnel: TunnelInterface?
    
    private var isReliableLink: Bool {
        return link?.isReliable ?? false
    }

    private var pushReply: SessionReply?
    
    private var nextPushRequestDate: Date?
    
    private var connectedDate: Date?

    private var lastPing: BidirectionalState<Date>
    
    private var isStopping: Bool
    
    /// The optional reason why the session stopped.
    public private(set) var stopError: Error?
    
    // MARK: Control
    
    private var controlChannel: ControlChannel
    
    private var authenticator: Authenticator?
    
    // MARK: Caching
    
    private let cachesURL: URL
    
    private var caURL: URL {
        return cachesURL.appendingPathComponent(Caches.ca)
    }
    
    private var clientCertificateURL: URL {
        return cachesURL.appendingPathComponent(Caches.clientCertificate)
    }
    
    private var clientKeyURL: URL {
        return cachesURL.appendingPathComponent(Caches.clientKey)
    }
    
    // MARK: Init

    /**
     Creates a VPN session.
     
     - Parameter queue: The `DispatchQueue` where to run the session loop.
     - Parameter configuration: The `SessionProxy.Configuration` to use for this session.
     */
    public init(queue: DispatchQueue, configuration: Configuration, cachesURL: URL) throws {
        self.queue = queue
        self.configuration = configuration
        self.cachesURL = cachesURL

        keys = [:]
        oldKeys = []
        negotiationKeyIdx = 0
        lastPing = BidirectionalState(withResetValue: Date.distantPast)
        isStopping = false
        
        if let tlsWrap = configuration.tlsWrap {
            switch tlsWrap.strategy {
            case .auth:
                controlChannel = try ControlChannel(withAuthKey: tlsWrap.key, digest: configuration.digest)

            case .crypt:
                controlChannel = try ControlChannel(withCryptKey: tlsWrap.key)
            }
        } else {
            controlChannel = ControlChannel()
        }
        
        // cache PEMs locally (mandatory for OpenSSL)
        let fm = FileManager.default
        try configuration.ca.pem.write(to: caURL, atomically: true, encoding: .ascii)
        if let container = configuration.clientCertificate {
            try container.pem.write(to: clientCertificateURL, atomically: true, encoding: .ascii)
        } else {
            try? fm.removeItem(at: clientCertificateURL)
        }
        if let container = configuration.clientKey {
            try container.pem.write(to: clientKeyURL, atomically: true, encoding: .ascii)
        } else {
            try? fm.removeItem(at: clientKeyURL)
        }
    }
    
    deinit {
        cleanup()

        let fm = FileManager.default
        for url in [caURL, clientCertificateURL, clientKeyURL] {
            try? fm.removeItem(at: url)
        }
    }
    
    // MARK: Public interface

    /**
     Establishes the link interface for this session. The interface must be up and running for sending and receiving packets.
     
     - Precondition: `link` is an active network interface.
     - Postcondition: The VPN negotiation is started.
     - Parameter link: The `LinkInterface` on which to establish the VPN session.
     */
    public func setLink(_ link: LinkInterface) {
        guard (self.link == nil) else {
            log.warning("Link interface already set!")
            return
        }

        log.debug("Starting VPN session")
        
        // WARNING: runs in notification source queue (we know it's "queue", but better be safe than sorry)
        tlsObserver = NotificationCenter.default.addObserver(forName: .TLSBoxPeerVerificationError, object: nil, queue: nil) { (notification) in
            let error = notification.userInfo?[TunnelKitErrorKey] as? Error
            self.queue.async {
                self.deferStop(.shutdown, error)
            }
        }
        
        self.link = link
        start()
    }
    
    /**
     Returns `true` if the current session can rebind to a new link with `rebindLink(...)`.

     - Returns: `true` if supports link rebinding.
     */
    public func canRebindLink() -> Bool {
        return (pushReply?.peerId != nil)
    }
    
    /**
     Rebinds the session to a new link if supported.
     
     - Precondition: `link` is an active network interface.
     - Postcondition: The VPN session is active.
     - Parameter link: The `LinkInterface` on which to establish the VPN session.
     - Seealso: `canRebindLink()`.
     */
    public func rebindLink(_ link: LinkInterface) {
        guard let _ = pushReply?.peerId else {
            log.warning("Session doesn't support link rebinding!")
            return
        }

        isStopping = false
        stopError = nil

        log.debug("Rebinding VPN session to a new link")
        self.link = link
        loopLink()
    }

    /**
     Establishes the tunnel interface for this session. The interface must be up and running for sending and receiving packets.
     
     - Precondition: `tunnel` is an active network interface.
     - Postcondition: The VPN data channel is open.
     - Parameter tunnel: The `TunnelInterface` on which to exchange the VPN data traffic.
     */
    public func setTunnel(tunnel: TunnelInterface) {
        guard (self.tunnel == nil) else {
            log.warning("Tunnel interface already set!")
            return
        }
        self.tunnel = tunnel
        loopTunnel()
    }

    /**
     Returns the current data bytes count.
 
     - Returns: The current data bytes count as a pair, inbound first.
     */
    public func dataCount() -> (Int, Int) {
        return controlChannel.currentDataCount()
    }
    
    /**
     Shuts down the session with an optional `Error` reason. Does nothing if the session is already stopped or about to stop.
     
     - Parameter error: An optional `Error` being the reason of the shutdown.
     */
    public func shutdown(error: Error?) {
        guard !isStopping else {
            log.warning("Ignore stop request, already stopping!")
            return
        }
        deferStop(.shutdown, error)
    }
    
    /**
     Shuts down the session with an optional `Error` reason and signals a reconnect flag to `SessionProxyDelegate.sessionDidStop(...)`. Does nothing if the session is already stopped or about to stop.
     
     - Parameter error: An optional `Error` being the reason of the shutdown.
     - Seealso: `SessionProxyDelegate.sessionDidStop(...)`
     */
    public func reconnect(error: Error?) {
        guard !isStopping else {
            log.warning("Ignore stop request, already stopping!")
            return
        }
        deferStop(.reconnect, error)
    }
    
    // Ruby: cleanup
    /**
     Cleans up the session resources.
     */
    public func cleanup() {
        log.info("Cleaning up...")

        if let observer = tlsObserver {
            NotificationCenter.default.removeObserver(observer)
            tlsObserver = nil
        }
        
        keys.removeAll()
        oldKeys.removeAll()
        negotiationKeyIdx = 0
        currentKeyIdx = nil
        
        nextPushRequestDate = nil
        connectedDate = nil
        authenticator = nil
        pushReply = nil
        link = nil
        if !(tunnel?.isPersistent ?? false) {
            tunnel = nil
        }
        
        isStopping = false
        stopError = nil
    }

    // MARK: Loop

    // Ruby: start
    private func start() {
        loopLink()
        hardReset()
    }
    
    private func loopNegotiation() {
        guard let link = link else {
            return
        }
        guard !keys.isEmpty else {
            return
        }

        guard !negotiationKey.didHardResetTimeOut(link: link) else {
            doReconnect(error: SessionError.negotiationTimeout)
            return
        }
        guard !negotiationKey.didNegotiationTimeOut(link: link) else {
            doShutdown(error: SessionError.negotiationTimeout)
            return
        }
            
        if !isReliableLink {
            pushRequest()
            flushControlQueue()
        }
        
        guard (negotiationKey.controlState == .connected) else {
            queue.asyncAfter(deadline: .now() + CoreConfiguration.tickInterval) { [weak self] in
                self?.loopNegotiation()
            }
            return
        }

        // let loop die when negotiation is complete
    }

    // Ruby: udp_loop
    private func loopLink() {
        let loopedLink = link
        loopedLink?.setReadHandler(queue: queue) { [weak self] (newPackets, error) in
            guard loopedLink === self?.link else {
                log.warning("Ignoring read from outdated LINK")
                return
            }
            if let error = error {
                log.error("Failed LINK read: \(error)")
                return
            }
            
            if let packets = newPackets, !packets.isEmpty {
                self?.maybeRenegotiate()

//                log.verbose("Received \(packets.count) packets from LINK")
                self?.receiveLink(packets: packets)
            }
        }
    }

    // Ruby: tun_loop
    private func loopTunnel() {
        tunnel?.setReadHandler(queue: queue) { [weak self] (newPackets, error) in
            if let error = error {
                log.error("Failed TUN read: \(error)")
                return
            }

            if let packets = newPackets, !packets.isEmpty {
//                log.verbose("Received \(packets.count) packets from \(self.tunnelName)")
                self?.receiveTunnel(packets: packets)
            }
        }
    }

    // Ruby: recv_link
    private func receiveLink(packets: [Data]) {
        guard shouldHandlePackets() else {
            return
        }
        
        lastPing.inbound = Date()

        var dataPacketsByKey = [UInt8: [Data]]()
        
        for packet in packets {
//            log.verbose("Received data from LINK (\(packet.count) bytes): \(packet.toHex())")

            guard let firstByte = packet.first else {
                log.warning("Dropped malformed packet (missing opcode)")
                continue
            }
            let codeValue = firstByte >> 3
            guard let code = PacketCode(rawValue: codeValue) else {
                log.warning("Dropped malformed packet (unknown code: \(codeValue))")
                continue
            }
//            log.verbose("Parsed packet with code \(code)")

            var offset = 1
            if (code == .dataV2) {
                guard packet.count >= offset + PacketPeerIdLength else {
                    log.warning("Dropped malformed packet (missing peerId)")
                    continue
                }
                offset += PacketPeerIdLength
            }

            if (code == .dataV1) || (code == .dataV2) {
                let key = firstByte & 0b111
                guard let _ = keys[key] else {
                    log.error("Key with id \(key) not found")
                    deferStop(.shutdown, SessionError.badKey)
                    return
                }

                // XXX: improve with array reference
                var dataPackets = dataPacketsByKey[key] ?? [Data]()
                dataPackets.append(packet)
                dataPacketsByKey[key] = dataPackets

                continue
            }

            let controlPacket: ControlPacket
            do {
                let parsedPacket = try controlChannel.readInboundPacket(withData: packet, offset: 0)
                handleAcks()
                if parsedPacket.code == .ackV1 {
                    continue
                }
                controlPacket = parsedPacket
            } catch let e {
                log.warning("Dropped malformed packet: \(e)")
                continue
//                deferStop(.shutdown, e)
//                return
            }
            if (code == .hardResetServerV2) && (negotiationKey.state != .hardReset) {
                deferStop(.shutdown, SessionError.staleSession)
                return
            } else if (code == .softResetV1) && (negotiationKey.state != .softReset) {
                softReset(isServerInitiated: true)
            }

            sendAck(for: controlPacket)

            let pendingInboundQueue = controlChannel.enqueueInboundPacket(packet: controlPacket)
            for inboundPacket in pendingInboundQueue {
                handleControlPacket(inboundPacket)
            }
        }

        // send decrypted packets to tunnel all at once
        for (keyId, dataPackets) in dataPacketsByKey {
            guard let sessionKey = keys[keyId] else {
                log.warning("Accounted a data packet for which the cryptographic key hadn't been found")
                continue
            }
            handleDataPackets(dataPackets, key: sessionKey)
        }
    }
    
    // Ruby: recv_tun
    private func receiveTunnel(packets: [Data]) {
        guard shouldHandlePackets() else {
            return
        }
        sendDataPackets(packets)
        lastPing.outbound = Date()
    }
    
    // Ruby: ping
    private func ping() {
        guard (currentKey?.controlState == .connected) else {
            return
        }
        
        let now = Date()
        guard (now.timeIntervalSince(lastPing.inbound) <= CoreConfiguration.pingTimeout) else {
            deferStop(.shutdown, SessionError.pingTimeout)
            return
        }

        // postpone ping if elapsed less than keep-alive
        if let interval = keepAliveInterval {
            let elapsed = now.timeIntervalSince(lastPing.outbound)
            guard (elapsed >= interval) else {
                scheduleNextPing(elapsed: elapsed)
                return
            }
        }

        log.debug("Send ping")
        sendDataPackets([DataPacket.pingString])
        lastPing.outbound = Date()

        scheduleNextPing()
    }
    
    private func scheduleNextPing(elapsed: TimeInterval = 0.0) {
        guard let interval = keepAliveInterval else {
            return
        }
        let remaining = min(interval, interval - elapsed)
        queue.asyncAfter(deadline: .now() + remaining) { [weak self] in
            self?.ping()
        }
    }
    
    // MARK: Handshake
    
    // Ruby: reset_ctrl
    private func resetControlChannel(forNewSession: Bool) {
        authenticator = nil
        do {
            try controlChannel.reset(forNewSession: forNewSession)
        } catch let e {
            deferStop(.shutdown, e)
        }
    }
    
    // Ruby: hard_reset
    private func hardReset() {
        log.debug("Send hard reset")

        resetControlChannel(forNewSession: true)
        pushReply = nil
        negotiationKeyIdx = 0
        let newKey = SessionKey(id: UInt8(negotiationKeyIdx))
        keys[negotiationKeyIdx] = newKey
        log.debug("Negotiation key index is \(negotiationKeyIdx)")

        let payload = hardResetPayload() ?? Data()
        negotiationKey.state = .hardReset
        guard !keys.isEmpty else {
            fatalError("Main loop must follow hard reset, keys are empty!")
        }
        loopNegotiation()
        enqueueControlPackets(code: .hardResetClientV2, key: UInt8(negotiationKeyIdx), payload: payload)
    }
    
    private func hardResetPayload() -> Data? {
        guard !(configuration.usesPIAPatches ?? false) else {
            let caMD5 = TLSBox.md5(forCertificatePath: caURL.path)
            log.debug("CA MD5 is: \(caMD5)")
            return try? PIAHardReset(
                caMd5Digest: caMD5,
                cipher: configuration.cipher,
                digest: configuration.digest
            ).encodedData()
        }
        return nil
    }
    
    // Ruby: soft_reset
    private func softReset(isServerInitiated: Bool) {
        if isServerInitiated {
            log.debug("Handle soft reset")
        } else {
            log.debug("Send soft reset")
        }
        
        resetControlChannel(forNewSession: false)
        negotiationKeyIdx = max(1, (negotiationKeyIdx + 1) % ProtocolMacros.numberOfKeys)
        let newKey = SessionKey(id: UInt8(negotiationKeyIdx))
        keys[negotiationKeyIdx] = newKey
        log.debug("Negotiation key index is \(negotiationKeyIdx)")

        negotiationKey.state = .softReset
        negotiationKey.softReset = true
        loopNegotiation()
        if !isServerInitiated {
            enqueueControlPackets(code: .softResetV1, key: UInt8(negotiationKeyIdx), payload: Data())
        }
    }
    
    // Ruby: on_tls_connect
    private func onTLSConnect() {
        log.debug("TLS.connect: Handshake is complete")

        negotiationKey.controlState = .preAuth
        
        do {
            authenticator = try Authenticator(credentials?.username, pushReply?.authToken ?? credentials?.password)
            try authenticator?.putAuth(into: negotiationKey.tls)
        } catch let e {
            deferStop(.shutdown, e)
            return
        }

        let cipherTextOut: Data
        do {
            cipherTextOut = try negotiationKey.tls.pullCipherText()
        } catch let e {
            if let _ = e.tunnelKitErrorCode() {
                log.error("TLS.auth: Failed pulling ciphertext (error: \(e))")
                shutdown(error: e)
                return
            }
            log.verbose("TLS.auth: Still can't pull ciphertext")
            return
        }

        log.debug("TLS.auth: Pulled ciphertext (\(cipherTextOut.count) bytes)")
        enqueueControlPackets(code: .controlV1, key: negotiationKey.id, payload: cipherTextOut)
    }
    
    // Ruby: push_request
    private func pushRequest() {
        guard (negotiationKey.controlState == .preIfConfig) else {
            return
        }
        if !isReliableLink {
            guard let targetDate = nextPushRequestDate, (Date() > targetDate) else {
                return
            }
        }
        
        log.debug("TLS.ifconfig: Put plaintext (PUSH_REQUEST)")
        try? negotiationKey.tls.putPlainText("PUSH_REQUEST\0")
        
        let cipherTextOut: Data
        do {
            cipherTextOut = try negotiationKey.tls.pullCipherText()
        } catch let e {
            if let _ = e.tunnelKitErrorCode() {
                log.error("TLS.auth: Failed pulling ciphertext (error: \(e))")
                shutdown(error: e)
                return
            }
            log.verbose("TLS.ifconfig: Still can't pull ciphertext")
            return
        }
        
        log.debug("TLS.ifconfig: Send pulled ciphertext (\(cipherTextOut.count) bytes)")
        enqueueControlPackets(code: .controlV1, key: negotiationKey.id, payload: cipherTextOut)
        
        if negotiationKey.softReset {
            completeConnection()
        }
        nextPushRequestDate = Date().addingTimeInterval(CoreConfiguration.retransmissionLimit)
    }
    
    private func maybeRenegotiate() {
        guard let renegotiatesAfter = configuration.renegotiatesAfter, renegotiatesAfter > 0 else {
            return
        }
        guard (negotiationKeyIdx == currentKeyIdx) else {
            return
        }
        
        let elapsed = -negotiationKey.startTime.timeIntervalSinceNow
        if (elapsed > renegotiatesAfter) {
            log.debug("Renegotiating after \(elapsed) seconds")
            softReset(isServerInitiated: false)
        }
    }
    
    private func completeConnection() {
        setupEncryption()
        authenticator = nil
        negotiationKey.controlState = .connected
        connectedDate = Date()
        transitionKeys()
    }
    
    // MARK: Control

    // Ruby: handle_ctrl_pkt
    private func handleControlPacket(_ packet: ControlPacket) {
        guard packet.key == negotiationKey.id else {
            log.error("Bad key in control packet (\(packet.key) != \(negotiationKey.id))")
//            deferStop(.shutdown, SessionError.badKey)
            return
        }
        
        // start new TLS handshake
        if ((packet.code == .hardResetServerV2) && (negotiationKey.state == .hardReset)) ||
            ((packet.code == .softResetV1) && (negotiationKey.state == .softReset)) {
 
            if negotiationKey.state == .hardReset {
                controlChannel.remoteSessionId = packet.sessionId
            }
            guard let remoteSessionId = controlChannel.remoteSessionId else {
                log.error("No remote sessionId (never set)")
                deferStop(.shutdown, SessionError.missingSessionId)
                return
            }
            guard packet.sessionId == remoteSessionId else {
                log.error("Packet session mismatch (\(packet.sessionId.toHex()) != \(remoteSessionId.toHex()))")
                deferStop(.shutdown, SessionError.sessionMismatch)
                return
            }

            negotiationKey.state = .tls

            log.debug("Start TLS handshake")

            negotiationKey.tlsOptional = TLSBox(
                caPath: caURL.path,
                clientCertificatePath: (configuration.clientCertificate != nil) ? clientCertificateURL.path : nil,
                clientKeyPath: (configuration.clientKey != nil) ? clientKeyURL.path : nil
            )
            do {
                try negotiationKey.tls.start()
            } catch let e {
                deferStop(.shutdown, e)
                return
            }

            let cipherTextOut: Data
            do {
                cipherTextOut = try negotiationKey.tls.pullCipherText()
            } catch let e {
                if let _ = e.tunnelKitErrorCode() {
                    log.error("TLS.connect: Failed pulling ciphertext (error: \(e))")
                    shutdown(error: e)
                    return
                }
                deferStop(.shutdown, e)
                return
            }

            log.debug("TLS.connect: Pulled ciphertext (\(cipherTextOut.count) bytes)")
            enqueueControlPackets(code: .controlV1, key: negotiationKey.id, payload: cipherTextOut)
        }
        // exchange TLS ciphertext
        else if ((packet.code == .controlV1) && (negotiationKey.state == .tls)) {
            guard let remoteSessionId = controlChannel.remoteSessionId else {
                log.error("No remote sessionId found in packet (control packets before server HARD_RESET)")
                deferStop(.shutdown, SessionError.missingSessionId)
                return
            }
            guard packet.sessionId == remoteSessionId else {
                log.error("Packet session mismatch (\(packet.sessionId.toHex()) != \(remoteSessionId.toHex()))")
                deferStop(.shutdown, SessionError.sessionMismatch)
                return
            }
            
            guard let cipherTextIn = packet.payload else {
                log.warning("TLS.connect: Control packet with empty payload?")
                return
            }

            log.debug("TLS.connect: Put received ciphertext (\(cipherTextIn.count) bytes)")
            try? negotiationKey.tls.putCipherText(cipherTextIn)

            let cipherTextOut: Data
            do {
                cipherTextOut = try negotiationKey.tls.pullCipherText()
                log.debug("TLS.connect: Send pulled ciphertext (\(cipherTextOut.count) bytes)")
                enqueueControlPackets(code: .controlV1, key: negotiationKey.id, payload: cipherTextOut)
            } catch let e {
                if let _ = e.tunnelKitErrorCode() {
                    log.error("TLS.connect: Failed pulling ciphertext (error: \(e))")
                    shutdown(error: e)
                    return
                }
                log.verbose("TLS.connect: No available ciphertext to pull")
            }
            
            if negotiationKey.shouldOnTLSConnect() {
                onTLSConnect()
            }

            do {
                let controlData = try controlChannel.currentControlData(withTLS: negotiationKey.tls)
                handleControlData(controlData)
            } catch _ {
            }
        }
    }

    // Ruby: handle_ctrl_data
    private func handleControlData(_ data: ZeroingData) {
        guard let auth = authenticator else {
            return
        }

        if CoreConfiguration.logsSensitiveData {
            log.debug("Pulled plain control data (\(data.count) bytes): \(data.toHex())")
        } else {
            log.debug("Pulled plain control data (\(data.count) bytes)")
        }

        auth.appendControlData(data)

        if (negotiationKey.controlState == .preAuth) {
            do {
                guard try auth.parseAuthReply() else {
                    return
                }
            } catch let e {
                deferStop(.shutdown, e)
                return
            }
            
            negotiationKey.controlState = .preIfConfig
            nextPushRequestDate = Date().addingTimeInterval(negotiationKey.softReset ? CoreConfiguration.softResetDelay : CoreConfiguration.retransmissionLimit)
            pushRequest()
        }
        
        for message in auth.parseMessages() {
            if CoreConfiguration.logsSensitiveData {
                log.debug("Parsed control message (\(message.count) bytes): \"\(message)\"")
            } else {
                log.debug("Parsed control message (\(message.count) bytes)")
            }
            handleControlMessage(message)
        }
    }

    // Ruby: handle_ctrl_msg
    private func handleControlMessage(_ message: String) {
        guard !message.hasPrefix("AUTH_FAILED") else {
            deferStop(.shutdown, SessionError.badCredentials)
            return
        }
        
        guard (negotiationKey.controlState == .preIfConfig) else {
            return
        }

        if CoreConfiguration.logsSensitiveData {
            log.debug("Received control message: \"\(message)\"")
        }
        
        let reply: PushReply
        do {
            guard let optionalReply = try PushReply(message: message) else {
                return
            }
            reply = optionalReply
            log.debug("Received PUSH_REPLY: \"\(reply.maskedDescription)\"")
        } catch let e {
            deferStop(.shutdown, e)
            return
        }
        
        pushReply = reply
        completeConnection()

        guard let remoteAddress = link?.remoteAddress else {
            fatalError("Could not resolve link remote address")
        }
        delegate?.sessionDidStart(self, remoteAddress: remoteAddress, reply: reply)

        scheduleNextPing()
    }
    
    // Ruby: transition_keys
    private func transitionKeys() {
        if let key = currentKey {
            oldKeys.append(key)
        }
        currentKeyIdx = negotiationKeyIdx
        cleanKeys()
    }
    
    // Ruby: clean_keys
    private func cleanKeys() {
        while (oldKeys.count > 1) {
            let key = oldKeys.removeFirst()
            keys.removeValue(forKey: key.id)
        }
    }
    
    // Ruby: q_ctrl
    private func enqueueControlPackets(code: PacketCode, key: UInt8, payload: Data) {
        guard let link = link else {
            log.warning("Not writing to LINK, interface is down")
            return
        }

        controlChannel.enqueueOutboundPackets(withCode: code, key: key, payload: payload, maxPacketSize: link.mtu)
        flushControlQueue()
    }
    
    // Ruby: flush_ctrl_q_out
    private func flushControlQueue() {
        let rawList: [Data]
        do {
            rawList = try controlChannel.writeOutboundPackets()
        } catch let e {
            log.warning("Failed control packet serialization: \(e)")
            deferStop(.shutdown, e)
            return
        }
        for raw in rawList {
            log.debug("Send control packet (\(raw.count) bytes): \(raw.toHex())")
        }
        
        // WARNING: runs in Network.framework queue
        link?.writePackets(rawList) { [weak self] (error) in
            if let error = error {
                self?.queue.sync {
                    log.error("Failed LINK write during control flush: \(error)")
                    self?.deferStop(.reconnect, SessionError.failedLinkWrite)
                    return
                }
            }
        }
    }
    
    // Ruby: setup_keys
    private func setupEncryption() {
        guard let auth = authenticator else {
            fatalError("Setting up encryption without having authenticated")
        }
        guard let sessionId = controlChannel.sessionId else {
            fatalError("Setting up encryption without a local sessionId")
        }
        guard let remoteSessionId = controlChannel.remoteSessionId else {
            fatalError("Setting up encryption without a remote sessionId")
        }
        guard let serverRandom1 = auth.serverRandom1, let serverRandom2 = auth.serverRandom2 else {
            fatalError("Setting up encryption without server randoms")
        }
        guard let pushReply = pushReply else {
            fatalError("Setting up encryption without a former PUSH_REPLY")
        }

        if CoreConfiguration.logsSensitiveData {
            log.debug("Set up encryption from the following components:")
            log.debug("\tpreMaster: \(auth.preMaster.toHex())")
            log.debug("\trandom1: \(auth.random1.toHex())")
            log.debug("\trandom2: \(auth.random2.toHex())")
            log.debug("\tserverRandom1: \(serverRandom1.toHex())")
            log.debug("\tserverRandom2: \(serverRandom2.toHex())")
            log.debug("\tsessionId: \(sessionId.toHex())")
            log.debug("\tremoteSessionId: \(remoteSessionId.toHex())")
        } else {
            log.debug("Set up encryption")
        }
        
        let pushedFraming = pushReply.compressionFraming
        if let negFraming = pushedFraming {
            log.info("\tNegotiated compression framing: \(negFraming)")
        }
        if let negPing = pushReply.ping {
            log.info("\tNegotiated keep-alive: \(negPing) seconds")
        }
        let pushedCipher = pushReply.cipher
        if let negCipher = pushedCipher {
            log.info("\tNegotiated cipher: \(negCipher.rawValue)")
        }

        let bridge: EncryptionBridge
        do {
            bridge = try EncryptionBridge(
                pushedCipher ?? configuration.cipher,
                configuration.digest,
                auth,
                sessionId,
                remoteSessionId
            )
        } catch let e {
            deferStop(.shutdown, e)
            return
        }

        negotiationKey.dataPath = DataPath(
            encrypter: bridge.encrypter(),
            decrypter: bridge.decrypter(),
            peerId: pushReply.peerId ?? PacketPeerIdDisabled,
            compressionFraming: (pushedFraming ?? configuration.compressionFraming).native,
            maxPackets: link?.packetBufferSize ?? 200,
            usesReplayProtection: CoreConfiguration.usesReplayProtection
        )
    }
    
    // MARK: Data

    // Ruby: handle_data_pkt
    private func handleDataPackets(_ packets: [Data], key: SessionKey) {
        controlChannel.addReceivedDataCount(packets.flatCount)
        do {
            guard let decryptedPackets = try key.decrypt(packets: packets) else {
                log.warning("Could not decrypt packets, is SessionKey properly configured (dataPath, peerId)?")
                return
            }
            guard !decryptedPackets.isEmpty else {
                return
            }

            tunnel?.writePackets(decryptedPackets, completionHandler: nil)
        } catch let e {
            guard !e.isTunnelKitError() else {
                deferStop(.shutdown, e)
                return
            }
            deferStop(.reconnect, e)
        }
    }
    
    // Ruby: send_data_pkt
    private func sendDataPackets(_ packets: [Data]) {
        guard let key = currentKey else {
            return
        }
        do {
            guard let encryptedPackets = try key.encrypt(packets: packets) else {
                log.warning("Could not encrypt packets, is SessionKey properly configured (dataPath, peerId)?")
                return
            }
            guard !encryptedPackets.isEmpty else {
                return
            }
            
            // WARNING: runs in Network.framework queue
            controlChannel.addSentDataCount(encryptedPackets.flatCount)
            link?.writePackets(encryptedPackets) { [weak self] (error) in
                if let error = error {
                    self?.queue.sync {
                        log.error("Data: Failed LINK write during send data: \(error)")
                        self?.deferStop(.reconnect, SessionError.failedLinkWrite)
                        return
                    }
                }
//                log.verbose("Data: \(encryptedPackets.count) packets successfully written to LINK")
            }
        } catch let e {
            guard !e.isTunnelKitError() else {
                deferStop(.shutdown, e)
                return
            }
            deferStop(.reconnect, e)
        }
    }
    
    // MARK: Acks
    
    private func handleAcks() {

        // retry PUSH_REQUEST if ack queue is empty (all sent packets were ack'ed)
        if isReliableLink && !controlChannel.hasPendingAcks() {
            pushRequest()
        }
    }
    
    // Ruby: send_ack
    private func sendAck(for controlPacket: ControlPacket) {
        log.debug("Send ack for received packetId \(controlPacket.packetId)")

        let raw: Data
        do {
            raw = try controlChannel.writeAcks(
                withKey: controlPacket.key,
                ackPacketIds: [controlPacket.packetId],
                ackRemoteSessionId: controlPacket.sessionId
            )
        } catch let e {
            deferStop(.shutdown, e)
            return
        }
        
        // WARNING: runs in Network.framework queue
        link?.writePacket(raw) { [weak self] (error) in
            if let error = error {
                self?.queue.sync {
                    log.error("Failed LINK write during send ack for packetId \(controlPacket.packetId): \(error)")
                    self?.deferStop(.reconnect, SessionError.failedLinkWrite)
                    return
                }
            }
            log.debug("Ack successfully written to LINK for packetId \(controlPacket.packetId)")
        }
    }
    
    // MARK: Stop
    
    private func shouldHandlePackets() -> Bool {
        return (!isStopping && !keys.isEmpty)
    }
    
    private func deferStop(_ method: StopMethod, _ error: Error?) {
        isStopping = true
        
        switch method {
        case .shutdown:
            doShutdown(error: error)
        
        case .reconnect:
            doReconnect(error: error)
        }
    }
    
    private func doShutdown(error: Error?) {
        if let error = error {
            log.error("Trigger shutdown (error: \(error))")
        } else {
            log.info("Trigger shutdown on request")
        }
        stopError = error
        delegate?.sessionDidStop(self, shouldReconnect: false)
    }
    
    private func doReconnect(error: Error?) {
        if let error = error {
            log.error("Trigger reconnection (error: \(error))")
        } else {
            log.info("Trigger reconnection on request")
        }
        stopError = error
        delegate?.sessionDidStop(self, shouldReconnect: true)
    }
}
