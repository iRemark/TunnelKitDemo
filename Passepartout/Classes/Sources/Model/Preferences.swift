//
//  Preferences.swift
//  Passepartout
//
//  Created by Davide De Rosa on 9/4/18.
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

protocol Preferences {
    var resolvesHostname: Bool { get }
    
    var disconnectsOnSleep: Bool { get }
    
    #if os(iOS)
    var trustsMobileNetwork: Bool { get }
    #endif
    
    var trustedWifis: [String: Bool] { get }
    
    var trustPolicy: TrustPolicy { get }
}

class EditablePreferences: Preferences, Codable {
    var resolvesHostname: Bool = true
    
    var disconnectsOnSleep: Bool = false
    
    #if os(iOS)
    var trustsMobileNetwork: Bool = false
    #endif
    
    var trustedWifis: [String: Bool] = [:]
    
    var trustPolicy: TrustPolicy = .disconnect
}
