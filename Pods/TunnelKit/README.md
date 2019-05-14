# TunnelKit

![iOS 11+](https://img.shields.io/badge/ios-11+-green.svg)
[![OpenSSL 1.1.0i](https://img.shields.io/badge/openssl-1.1.0i-d69c68.svg)](https://www.openssl.org/news/openssl-1.1.0-notes.html)
[![License GPLv3](https://img.shields.io/badge/license-GPLv3-lightgray.svg)](LICENSE)
[![Tweet](https://img.shields.io/twitter/url/http/shields.io.svg?style=social)](https://twitter.com/intent/tweet?url=https%3A%2F%2Fgithub.com%2Fkeeshux%2Ftunnelkit&via=keeshux&text=TunnelKit%2C%20a%20non-official%20%23OpenVPN%20client%20for%20%23Apple%20platforms&hashtags=iOS%2CmacOS)

This library provides a simplified Swift/Obj-C implementation of the OpenVPN® protocol for the Apple platforms. The crypto layer is built on top of [OpenSSL][dep-openssl] 1.1.0i, which in turn enables support for a certain range of encryption and digest algorithms.

<a href="https://www.patreon.com/keeshux"><img src="https://c5.patreon.com/external/logo/become_a_patron_button@2x.png" width="160"></a>

## Getting started

The client is known to work with [OpenVPN®][openvpn] 2.3+ servers. Key renegotiation and replay protection are also included, but full-fledged configuration files (.ovpn) are not currently supported.

- [x] Handshake and tunneling over UDP or TCP
- [x] Ciphers
    - AES-CBC (128/192/256 bit)
    - AES-GCM (128/192/256 bit, 2.4)
- [x] HMAC digests
    - SHA-1
    - SHA-2 (224/256/384/512 bit)
- [x] NCP (Negotiable Crypto Parameters, 2.4)
    - Server-side
- [x] TLS handshake
    - Server validation (CA, EKU)
    - Client certificate
- [x] TLS wrapping
    - Authentication (`--tls-auth`)
    - Encryption (`--tls-crypt`)
- [x] Compression framing
    - Disabled
    - Compress (2.4)
    - LZO (deprecated in 2.4)
- [x] Replay protection (hardcoded window)

The library therefore supports compression framing, just not compression. Remember to match server-side compression framing in order to avoid a confusing loss of data packets. E.g. if server has `comp-lzo no`, client must use `compressionFraming = .compLZO`.

## Installation

### Requirements

- iOS 11.0+ / macOS 10.11+
- Xcode 10+ (Swift 4.2)
- Git (preinstalled with Xcode Command Line Tools)
- Ruby (preinstalled with macOS)
- [CocoaPods 1.4.0][dep-cocoapods]
- [jazzy][dep-jazzy] (optional, for documentation)

It's highly recommended to use the Git and Ruby packages provided by [Homebrew][dep-brew].

### CocoaPods

To use with CocoaPods just add this to your Podfile:

```ruby
pod 'TunnelKit'
```

### Testing

Download the library codebase locally:

    $ git clone https://github.com/keeshux/tunnelkit.git

Assuming you have a [working CocoaPods environment][dep-cocoapods], setting up the library workspace only requires installing the pod dependencies:

    $ pod install

After that, open `TunnelKit.xcworkspace` in Xcode and run the unit tests found in the `TunnelKitTests` target. A simple CMD+U while on `TunnelKit-iOS` should do that as well.

#### Demo

There is a `Demo` directory containing a simple app for testing the tunnel, called `BasicTunnel`. As usual, prepare for CocoaPods:

    $ pod install

then open `Demo.xcworkspace` and run the `BasicTunnel-iOS` target.

For the VPN to work properly, the `BasicTunnel` demo requires:

- _App Groups_ and _Keychain Sharing_ capabilities
- App IDs with _Packet Tunnel_ entitlements

both in the main app and the tunnel extension target.

In order to test connection to your own server, modify the file `Demo/BasicTunnel-[iOS|macOS]/ViewController.swift` and make sure to set `ca` to the PEM encoded certificate of your VPN server's CA.

Example:

    private let ca = CryptoContainer(pem: """
	-----BEGIN CERTIFICATE-----
	MIIFJDCC...
	-----END CERTIFICATE-----
    """)

## Documentation

The library is split into two modules, in order to decouple the low-level protocol implementation from the platform-specific bridging, namely the [NetworkExtension][ne-home] VPN framework.

Full documentation of the public interface is available and can be generated with [jazzy][dep-jazzy]. After installing the jazzy Ruby gem with:

    $ gem install jazzy

enter the root directory of the repository and run:

    $ jazzy

The generated output is stored into the `docs` directory in HTML format.

### Core

Here you will find the low-level entities on top of which the connection is established. Code is mixed Swift and Obj-C, most of it is not exposed to consumers. The *Core* module depends on OpenSSL and is mostly platform-agnostic.

The entry point is the `SessionProxy` class. The networking layer is fully abstract and delegated externally with the use of opaque `IOInterface` (`LinkInterface` and `TunnelInterface`) and `SessionProxyDelegate` protocols.

### AppExtension

The goal of this module is packaging up a black box implementation of a [NEPacketTunnelProvider][ne-ptp], which is the essential part of a Packet Tunnel Provider app extension. You will find the main implementation in the `TunnelKitProvider` class.

Currently, the extension supports VPN over both [UDP][ne-udp] and [TCP][ne-tcp] sockets. A debug log snapshot is optionally maintained and shared to host apps via `UserDefaults` in a shared App Group.

## License

### Part I

This project is licensed under the [GPLv3][license-content].

### Part II

As seen in [libsignal-protocol-c][license-signal]:

> Additional Permissions For Submission to Apple App Store: Provided that you are otherwise in compliance with the GPLv3 for each covered work you convey (including without limitation making the Corresponding Source available in compliance with Section 6 of the GPLv3), the Author also grants you the additional permission to convey through the Apple App Store non-source executable versions of the Program as incorporated into each applicable covered work as Executable Versions only under the Mozilla Public License version 2.0 (https://www.mozilla.org/en-US/MPL/2.0/).

### Contributing

By contributing to this project you are agreeing to the terms stated in the [Contributor License Agreement (CLA)][contrib-cla].

For more details please see [CONTRIBUTING][contrib-readme].

## Credits

- [PIATunnel][dep-piatunnel-repo] - Copyright (c) 2018-Present Private Internet Access
- [SwiftyBeaver][dep-swiftybeaver-repo] - Copyright (c) 2015 Sebastian Kreutzberger

This product includes software developed by the OpenSSL Project for use in the OpenSSL Toolkit. ([https://www.openssl.org/][dep-openssl])

© 2002-2018 OpenVPN Inc. - OpenVPN is a registered trademark of OpenVPN Inc.

## Contacts

Twitter: [@keeshux][about-twitter]

Website: [davidederosa.com][about-website]

[openvpn]: https://openvpn.net/index.php/open-source/overview.html

[dep-cocoapods]: https://guides.cocoapods.org/using/getting-started.html
[dep-jazzy]: https://github.com/realm/jazzy
[dep-brew]: https://brew.sh/
[dep-openssl]: https://www.openssl.org/

[ne-home]: https://developer.apple.com/documentation/networkextension
[ne-ptp]: https://developer.apple.com/documentation/networkextension/nepackettunnelprovider
[ne-udp]: https://developer.apple.com/documentation/networkextension/nwudpsession
[ne-tcp]: https://developer.apple.com/documentation/networkextension/nwtcpconnection

[license-content]: LICENSE
[license-signal]: https://github.com/signalapp/libsignal-protocol-c#license
[license-mit]: https://choosealicense.com/licenses/mit/
[contrib-cla]: CLA.rst
[contrib-readme]: CONTRIBUTING.md

[dep-piatunnel-repo]: https://github.com/pia-foss/tunnel-apple
[dep-swiftybeaver-repo]: https://github.com/SwiftyBeaver/SwiftyBeaver

[about-twitter]: https://twitter.com/keeshux
[about-website]: https://davidederosa.com
[about-patreon]: https://www.patreon.com/keeshux
