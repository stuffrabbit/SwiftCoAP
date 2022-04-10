//
//  File.swift
//  
//
//  Created by Hoang Viet Tran on 04/04/2022.
//

import Network
@testable import SwiftCoAP
import XCTest

class MockSCCoAPTransportLayer: SCCoAPTransportLayerProtocol {
    private let operationsQueue = DispatchQueue(label: "swiftcoap.queue.operations", qos: .default)
    var messageToSend: SCMessage?
    var canceledMessageTransmission: Bool = false
    var canceledMessageTransmissionEndpoint: NWEndpoint?
    var canceledConnection: Bool = false
    var canceledConnectionEndpoint: NWEndpoint?
    var closedAllTransmissions: Bool = false

    var client: SCClientTests
    
    init(client: SCClientTests) {
        self.client = client
    }
    
    func sendCoAPMessage(_ message: SCMessage, toEndpoint endpoint: NWEndpoint, token: UInt64?, delegate: SCCoAPTransportLayerDelegate?) throws {
        messageToSend = message

    }
    
    func getMessageId(for endpoint:NWEndpoint) -> UInt16 {
        return 123
    }
    
    func cancelMessageTransmission(to endpoint: NWEndpoint, withToken: UInt64) {
        canceledMessageTransmission = true
        canceledMessageTransmissionEndpoint = endpoint
    }
    
    func cancelConnection(to endpoint: NWEndpoint) {
        canceledConnection = true
        canceledConnectionEndpoint = endpoint
    }
    
    func closeAllTransmissions() {
        closedAllTransmissions = true
    }
}
