//
//  ProviderConnectionProfile.swift
//  Passepartout
//
//  Created by Davide De Rosa on 9/2/18.
//  Copyright (c) 2018 Thor. All rights reserved.
//
//  https://github.com/passepartoutvpn
//
//  This file is part of Passepartout.
//
//  Passepartout is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Passepartout is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with Passepartout.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation
import TunnelKit

class ProviderConnectionProfile: ConnectionProfile, Codable, Equatable {
    let name: Infrastructure.Name

    var infrastructure: Infrastructure {
        return InfrastructureFactory.shared.get(name)
    }

    var poolId: String {
        didSet {
            validateEndpoint()
        }
    }

    var pool: Pool? {
        return infrastructure.pool(for: poolId) ?? infrastructure.pool(for: infrastructure.defaults.pool)
    }

    var presetId: String {
        didSet {
            validateEndpoint()
        }
    }
    
    var preset: InfrastructurePreset? {
        return infrastructure.preset(for: presetId)
    }
    
    var manualAddress: String?

    var manualProtocol: TunnelKitProvider.EndpointProtocol?
    
    var usesProviderEndpoint: Bool {
        return (manualAddress != nil) || (manualProtocol != nil)
    }
    
    init(name: Infrastructure.Name) {
        self.name = name
        poolId = ""
        presetId = ""

        username = nil

        poolId = infrastructure.defaults.pool
        presetId = infrastructure.defaults.preset
    }
    
    func sortedPools() -> [Pool] {
        return infrastructure.pools.sorted()
    }
    
    private func validateEndpoint() {
        guard let pool = pool, let preset = preset else {
            manualAddress = nil
            manualProtocol = nil
            return
        }
        if let address = manualAddress, !pool.hasAddress(address) {
            manualAddress = nil
        }
        if let proto = manualProtocol, !preset.hasProtocol(proto) {
            manualProtocol = nil
        }
    }
    
    // MARK: ConnectionProfile
    
    let context: Context = .provider

    var id: String {
        return name.rawValue
    }
    
    var username: String?
    
    var requiresCredentials: Bool {
        return true
    }
    
    func generate(from configuration: TunnelKitProvider.Configuration, preferences: Preferences) throws -> TunnelKitProvider.Configuration {
        guard let pool = pool else {
            preconditionFailure("Nil pool?")
        }
        guard let preset = preset else {
            preconditionFailure("Nil preset?")
        }

//        assert(!pool.numericAddresses.isEmpty)

        // XXX: copy paste, error prone
        var builder = preset.configuration.builder()
        builder.mtu = configuration.mtu
        builder.shouldDebug = configuration.shouldDebug
        builder.debugLogFormat = configuration.debugLogFormat

        if let address = manualAddress {
            builder.prefersResolvedAddresses = true
            builder.resolvedAddresses = [address]
        } else {
            builder.prefersResolvedAddresses = !preferences.resolvesHostname
            builder.resolvedAddresses = pool.addresses(sorted: false)
        }
        
        if let proto = manualProtocol {
            builder.endpointProtocols = [proto]
        } else {
            builder.endpointProtocols = preset.configuration.endpointProtocols
//            builder.endpointProtocols = [
//                TunnelKitProvider.EndpointProtocol(.udp, 8080),
//                TunnelKitProvider.EndpointProtocol(.tcp, 443)
//            ]
        }
        return builder.build()
    }

    func with(newId: String) -> ConnectionProfile {
        fatalError("Cannot rename a ProviderConnectionProfile")
    }
}

extension ProviderConnectionProfile {
    static func ==(lhs: ProviderConnectionProfile, rhs: ProviderConnectionProfile) -> Bool {
        return lhs.id == rhs.id
    }
}

extension ProviderConnectionProfile {
    var mainAddress: String {
        assert(pool != nil, "Getting provider main address but no pool set")
        return pool?.hostname ?? ""
    }
    
    var addresses: [String] {
        return pool?.addresses(sorted: true) ?? []
    }
    
    var protocols: [TunnelKitProvider.EndpointProtocol] {
        return preset?.configuration.endpointProtocols ?? []
    }
    
    var canCustomizeEndpoint: Bool {
        return true
    }
    
    var customAddress: String? {
        return manualAddress
    }

    var customProtocol: TunnelKitProvider.EndpointProtocol? {
        return manualProtocol
    }
}
