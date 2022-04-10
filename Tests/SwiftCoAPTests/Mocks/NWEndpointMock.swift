//
//  File.swift
//  
//
//  Created by Hoang Viet Tran on 04/04/2022.
//

import Network

class NWEndpointMock {
    let device1Host: String = "coap://coap.me/relay"
    let device1Port: UInt16 = 5683
    let device2Host: String = "esp32c3-mdns._namicoap._udplocal"
    let device2Port: UInt16 = 5683
    
    var endpoint1: NWEndpoint
    var endpoint2: NWEndpoint
    
    init() {
        endpoint1 = NWEndpoint.hostPort(host: NWEndpoint.Host(device1Host), port: NWEndpoint.Port(rawValue: device1Port)!)
        endpoint2 = NWEndpoint.hostPort(host: NWEndpoint.Host(device2Host), port: NWEndpoint.Port(rawValue: device2Port)!)
    }
}
