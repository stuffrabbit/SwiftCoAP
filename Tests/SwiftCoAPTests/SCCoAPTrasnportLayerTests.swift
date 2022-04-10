// Copyright (c) nami.ai

import XCTest
@testable import SwiftCoAP
import Network

class SCCoAPTransportLayerTests: XCTestCase {
    private var coapTransportLayer: SCCoAPUDPTransportLayer!
    private var endpoint1 = NWEndpointMock().endpoint1
    private var endpoint2 = NWEndpointMock().endpoint2
    
    private var host: String?
    private var port: UInt16?
    private var endpoint: NWEndpoint?
    private var dataFromHost: Data?
    private var dataFromEndpoint: Data?
    private var error: NSError?
    private var transportLayerExpectation: XCTestExpectation!
    
    override func setUp() {
        let parameters = NWParameters(dtls: NWProtocolTLS.Options(), udp: NWProtocolUDP.Options())
        coapTransportLayer = SCCoAPUDPTransportLayer(networkParameters: parameters)
    }

    override func tearDown() {
        coapTransportLayer = nil
    }

    func testGetMessageIdIsNotEqualIfCalledAgain() {
        let messageId = coapTransportLayer.getMessageId(for: endpoint1)
        let messageId2 = coapTransportLayer.getMessageId(for: endpoint1)
        
        XCTAssertNotEqual(messageId, messageId2)
    }
    
    func testCancelConnectionCreatedByMustGetConnection() {
        let _ = coapTransportLayer.mustGetConnection(forEndpoint: endpoint1)
        coapTransportLayer.cancelConnection(to: endpoint1)
        XCTAssertTrue(coapTransportLayer.connections.isEmpty)
    }
    
    func testCancelConnectionCreatedBySendCoAPMessage() throws {
        let msg = SCMessage(code: SCCodeValue(classValue: 0, detailValue: 01)!, type: .confirmable, payload: nil)
        try coapTransportLayer.sendCoAPMessage(msg, toEndpoint: endpoint1, token: nil, delegate: nil)
        coapTransportLayer.cancelConnection(to: endpoint1)
        XCTAssertTrue(coapTransportLayer.connections.isEmpty)
    }
    
    func testAfterSendCoAPMessageConnectionIsNotNil() throws {
        let msg = SCMessage(code: SCCodeValue(classValue: 0, detailValue: 01)!, type: .confirmable, payload: nil)
        try coapTransportLayer.sendCoAPMessage(msg, toEndpoint: endpoint1, token: nil, delegate: nil)
        let expectedConnection = coapTransportLayer.connections[endpoint1]
        
        XCTAssertNotNil(expectedConnection)
    }
    
    func testMustGetConnectionReturnsSameConnectionAfterSendingCoAPMessage() throws {
        let msg = SCMessage(code: SCCodeValue(classValue: 0, detailValue: 01)!, type: .confirmable, payload: nil)
        try coapTransportLayer.sendCoAPMessage(msg, toEndpoint: endpoint1, token: nil, delegate: nil)
        let expectedConnection = coapTransportLayer.connections[endpoint1]
        let connection = coapTransportLayer.mustGetConnection(forEndpoint: endpoint1)
        
        XCTAssertNotNil(connection)
        XCTAssertEqual(expectedConnection!.connection.endpoint, connection.endpoint)
    }
    
    func testSendCoAPMessageNoThrows() {
        let msg = SCMessage(code: SCCodeValue(classValue: 0, detailValue: 01)!, type: .confirmable, payload: nil)
        XCTAssertNoThrow(try coapTransportLayer.sendCoAPMessage(msg, toEndpoint: endpoint1, token: nil, delegate: nil))
    }
    
    func testSendCoAPMessageToDifferentEndpointsHasMatchingNumberOfConnections() throws {
        let msg = SCMessage(code: SCCodeValue(classValue: 0, detailValue: 01)!, type: .confirmable, payload: nil)
        try coapTransportLayer.sendCoAPMessage(msg, toEndpoint: endpoint1, token: nil, delegate: nil)
        try coapTransportLayer.sendCoAPMessage(msg, toEndpoint: endpoint2, token: nil, delegate: nil)
        
        XCTAssertEqual(coapTransportLayer.connections.count, 2)
    }
    
    func testSendCoAPMessageCreatesNewConnectionAfterCancel() throws {
        coapTransportLayer.cancelConnection(to: endpoint1)
        
        XCTAssertTrue(coapTransportLayer.connections.isEmpty)
        
        let msg = SCMessage(code: SCCodeValue(classValue: 0, detailValue: 01)!, type: .confirmable, payload: nil)
        try coapTransportLayer.sendCoAPMessage(msg, toEndpoint: endpoint1, token: nil, delegate: nil)

        XCTAssertFalse(coapTransportLayer.connections.isEmpty)
    }
    
    func testSendCoAPMessageDoesNotCreateMultipleConnections() throws {
        let msg = SCMessage(code: SCCodeValue(classValue: 0, detailValue: 01)!, type: .confirmable, payload: nil)
        try coapTransportLayer.sendCoAPMessage(msg, toEndpoint: endpoint1, token: nil, delegate: nil)
        try coapTransportLayer.sendCoAPMessage(msg, toEndpoint: endpoint1, token: nil, delegate: nil)
        try coapTransportLayer.sendCoAPMessage(msg, toEndpoint: endpoint1, token: nil, delegate: nil)
        
        XCTAssertEqual(coapTransportLayer.connections.count, 1)
    }
    
    func testSendCoAPMessageSetsDelegate() throws {
        let msg = SCMessage(code: SCCodeValue(classValue: 0, detailValue: 01)!, type: .confirmable, payload: nil)
        try coapTransportLayer.sendCoAPMessage(msg, toEndpoint: endpoint1, token: 123, delegate: self)
        
        XCTAssertFalse(coapTransportLayer.transportLayerDelegates.isEmpty)
    }
    
    func testNotifiyDelegateAboutError() throws {
        let msg = SCMessage(code: SCCodeValue(classValue: 0, detailValue: 01)!, type: .confirmable, payload: nil)
        transportLayerExpectation = expectation(description: "TransportLayer error")
        try coapTransportLayer.sendCoAPMessage(msg, toEndpoint: endpoint1, token: 123, delegate: self)
        coapTransportLayer.notifyDelegatesAboutError(for: endpoint1, error: SCCoAPTransportLayerError.encodeError)
        
        waitForExpectations(timeout: 5)
        XCTAssertNotNil(self.error)
    }
    
    func testReceivedNonConfirmableMessage() throws {
        let mockEndpoint = NWEndpointMock()
        let msg = SCMessage(code: SCCodeValue(classValue: 0, detailValue: 02)!, type: .nonConfirmable, payload: nil)
        msg.messageId = coapTransportLayer.getMessageId(for: endpoint1)
        let id = MessageTransportIdentifier(token: 0, endpoint: endpoint1)
        let parameters = NWParameters(dtls: NWProtocolTLS.Options(), udp: NWProtocolUDP.Options())
        let messageTransportDelegate = MessageTransportDelegate(delegate: self, observation: msg.isObservation())
        coapTransportLayer.transportLayerDelegates[id] = messageTransportDelegate
        XCTAssertFalse(coapTransportLayer.transportLayerDelegates.isEmpty)
        XCTAssertTrue(coapTransportLayer.transportLayerDelegates[id]?.delegate === messageTransportDelegate.delegate)
        if let data = try DataHelper.secureRandomData(count: 10) {
            transportLayerExpectation = expectation(description: "Received data from endpoint")
            coapTransportLayer.handleReceivedMessage(msg, connection: NWConnection(host: NWEndpoint.Host(mockEndpoint.device1Host), port: NWEndpoint.Port(rawValue: mockEndpoint.device1Port) ?? 111, using: parameters), rawData: data)
            
            waitForExpectations(timeout: 5)
            XCTAssertNotNil(self.dataFromEndpoint)
        }
    }
    
    func testReceivedMessageDidReceiveDataWillNotBeCalled() throws {
        let mockEndpoint = NWEndpointMock()
        let msg = SCMessage(code: SCCodeValue(classValue: 0, detailValue: 02)!, type: .nonConfirmable, payload: nil)
        msg.messageId = coapTransportLayer.getMessageId(for: endpoint1)
        // TODO: verify whether it's bug or expected behavior
        // setting token will result in received data will not be called
        let id = MessageTransportIdentifier(token: 123, endpoint: endpoint1)
        let parameters = NWParameters(dtls: NWProtocolTLS.Options(), udp: NWProtocolUDP.Options())
        let messageTransportDelegate = MessageTransportDelegate(delegate: self, observation: msg.isObservation())
        coapTransportLayer.transportLayerDelegates[id] = messageTransportDelegate
        XCTAssertFalse(coapTransportLayer.transportLayerDelegates.isEmpty)
        XCTAssertTrue(coapTransportLayer.transportLayerDelegates[id]?.delegate === messageTransportDelegate.delegate)
        if let data = try DataHelper.secureRandomData(count: 10) {
            transportLayerExpectation = expectation(description: "Received data from endpoint")
            transportLayerExpectation.isInverted = true
            coapTransportLayer.handleReceivedMessage(msg, connection: NWConnection(host: NWEndpoint.Host(mockEndpoint.device1Host), port: NWEndpoint.Port(rawValue: mockEndpoint.device1Port) ?? 111, using: parameters), rawData: data)
            
            waitForExpectations(timeout: 5)
            XCTAssertNil(self.dataFromEndpoint)
        }
    }

}

extension SCCoAPTransportLayerTests: SCCoAPTransportLayerDelegate {
    func transportLayerObject(_ transportLayerObject: SCCoAPTransportLayerProtocol, didReceiveData data: Data, fromHost host: String, port: UInt16) {
        self.dataFromHost = data
        self.host = host
        self.port = port
        
        transportLayerExpectation.fulfill()
    }
    
    func transportLayerObject(_ transportLayerObject: SCCoAPTransportLayerProtocol, didReceiveData data: Data, fromEndpoint endpoint: NWEndpoint) {
        self.dataFromEndpoint = data
        self.endpoint = endpoint
        
        transportLayerExpectation.fulfill()
    }
    
    // Error occured. Provide an appropriate NSError object.
    func transportLayerObject(_ transportLayerObject: SCCoAPTransportLayerProtocol, didFailWithError error: NSError) {
        self.dataFromHost = nil
        self.host = nil
        self.port = nil
        self.dataFromEndpoint = nil
        self.endpoint = nil
        self.error = error
        
        transportLayerExpectation.fulfill()
    }
}
