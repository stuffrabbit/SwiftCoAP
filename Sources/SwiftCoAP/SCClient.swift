//
//  SCClient.swift
//  SwiftCoAP
//
//  Created by Wojtek Kordylewski on 03.05.15.
//  Copyright (c) 2015 Wojtek Kordylewski. All rights reserved.
//

import Foundation
import Network
import os.log

//MARK: - SC Client Delegate Protocol declaration

public protocol SCClientDelegate: AnyObject {
    
    //Tells the delegate that a valid CoAP message was received
    func swiftCoapClient(_ client: SCClient, didReceiveMessage message: SCMessage)
    
    //Tells the delegate that an error occured during or before transmission (refer to the "SCClientErrorCode" Enum)
    func swiftCoapClient(_ client: SCClient, didFailWithError error: NSError)
    
    //Tells the delegate that the respective message was sent. The property "number" indicates the amount of (re-)transmission attempts
    func swiftCoapClient(_ client: SCClient, didSendMessage message: SCMessage, number: Int)
}


//MARK: - SC Client Error Code Enumeration

public enum SCClientErrorCode: Int {
    case transportLayerSendError, messageInvalidForSendingError, receivedInvalidMessageError, noResponseExpectedError, proxyingError
    
    func descriptionString() -> String {
        switch self {
        case .transportLayerSendError:
            return "Failed to send data via the given Transport Layer"
        case .messageInvalidForSendingError:
            return "CoAP-Message is not valid"
        case .receivedInvalidMessageError:
            return "Data received was not a valid CoAP Message"
        case .noResponseExpectedError:
            return "The recipient does not respond"
        case .proxyingError:
            return "HTTP-URL Request could not be sent"
        }
    }
}


//MARK: - SC Client IMPLEMENTATION

public class SCClient: NSObject {
    
    //MARK: Constants and Properties
    
    //CONSTANTS
    let kMaxObserveOptionValue: UInt = 8388608
    
    //INTERNAL PROPERTIES (allowed to modify)
    
    public weak var delegate: SCClientDelegate?
    public var sendToken = true   //If true, a token with 4-8 Bytes is sent
    public var autoBlock1SZX: UInt? = 2 { didSet { if let newValue = autoBlock1SZX { autoBlock1SZX = min(6, newValue) } } } //If not nil, Block1 transfer will be used automatically when the payload size exceeds the value 2^(autoBlock1SZX + 4). Valid Values: 0-6.
    
    public var httpProxyingData: (hostName: String, port: UInt16)?     //If not nil, all messages will be sent via http to the given proxy address
    public var cachingActive = false   //Activates caching
    public var disableRetransmissions = false
    
    //READ-ONLY PROPERTIES
    
    fileprivate (set) var isMessageInTransmission = false   //Indicates whether a message is in transmission and/or responses are still expected (e.g. separate, block, observe)
    
    //PRIVATE PROPERTIES
    
    fileprivate var transportLayerObject: SCCoAPTransportLayerProtocol!
    fileprivate var transmissionTimer: Timer!
    fileprivate var messageInTransmission: SCMessage!
    fileprivate var currentMessageId: UInt16 = UInt16(arc4random_uniform(0xFFFF) &+ 1)
    fileprivate var retransmissionCounter = 0
    fileprivate var currentTransmitWait = 0.0
    fileprivate var recentNotificationInfo: (Date, UInt)!
    lazy fileprivate var cachedMessagePairs = [SCMessage : SCMessage]()

    
    //MARK: Internal Methods (allowed to use)
    
    public init(delegate: SCClientDelegate?, transportLayerObject: SCCoAPTransportLayerProtocol = SCCoAPUDPTransportLayer()) {
        self.delegate = delegate
        super.init()
        self.transportLayerObject = transportLayerObject
        self.transportLayerObject.transportLayerDelegate = self
    }

    public func sendCoAPMessage(_ message: SCMessage, hostName: String, port: UInt16) {
        sendCoAPMessage(
            message,
            endpoint: NWEndpoint.hostPort(
                host: NWEndpoint.Host(hostName),
                port: NWEndpoint.Port(rawValue: port)!
            )
        )
    }
    
    public func sendCoAPMessage(_ message: SCMessage, endpoint: NWEndpoint) {
        currentMessageId = (currentMessageId % 0xFFFF) + 1
        
        message.endpoint = endpoint
        message.messageId = currentMessageId
        message.timeStamp = Date()
        
        messageInTransmission = message
        
        if sendToken {
            message.token = UInt64(arc4random_uniform(0xFFFFFFFF) + 1) + (UInt64(arc4random_uniform(0xFFFFFFFF) + 1) << 32)
        }
        
        if cachingActive && message.code == SCCodeValue(classValue: 0, detailValue: 01) {
            for cachedMessage in cachedMessagePairs.keys {
                if cachedMessage.equalForCachingWithMessage(message) {
                    if cachedMessage.isFresh() {
                        if message.options[SCOption.observe.rawValue] == nil { cachedMessage.options[SCOption.observe.rawValue] = nil }
                        delegate?.swiftCoapClient(self, didReceiveMessage: cachedMessagePairs[cachedMessage]!)
                        handleBlock2WithMessage(cachedMessagePairs[cachedMessage]!)
                        return
                    }
                    else {
                        cachedMessagePairs[cachedMessage] = nil
                        break
                    }
                }
            }
        }
        
        if  httpProxyingData != nil {
            sendHttpMessageFromCoAPMessage(message)
        }
        else {
            if message.blockBody == nil, let autoB1SZX = autoBlock1SZX {
                let fixedByteSize = pow(2, Double(autoB1SZX) + 4)
                if let payload = message.payload {
                    let blocksCount = ceil(Double(payload.count) / fixedByteSize)
                    if blocksCount > 1 {
                        message.blockBody = payload
                        let blockValue = 8 + UInt(autoB1SZX)
                        sendBlock1MessageForCurrentContext(payload: payload.subdata(in: (0 ..< Int(fixedByteSize))), blockValue: blockValue)
                        return
                    }
                }
            }
            
            initiateSending()
        }
    }
    
    
    // Cancels observe directly, sending the previous message with an Observe-Option Value of 1. Only effective, if the previous message initiated a registration as observer with the respective server. To cancel observer indirectly (forget about the current state) call "closeTransmission()" or send another Message (this cleans up the old state automatically)
    public func cancelObserve() {
        let cancelMessage = SCMessage(code: SCCodeValue(classValue: 0, detailValue: 01)!, type: .nonConfirmable, payload: nil)
        cancelMessage.token = messageInTransmission.token
        cancelMessage.options = messageInTransmission.options
        currentMessageId = (currentMessageId % 0xFFFF) + 1
        cancelMessage.messageId = currentMessageId
        cancelMessage.endpoint = messageInTransmission.endpoint
        var cancelByte: UInt8 = 1
        cancelMessage.options[SCOption.observe.rawValue] = [Data(bytes: &cancelByte, count: 1)]
        if let messageData = cancelMessage.toData() {
            sendCoAPMessageOverTransportLayerWithData(messageData, endpoint: messageInTransmission.endpoint!)
        }
    }
    
    
    //Closes the transmission. It is recommended to call this method anytime you do not expect to receive a response any longer.
    
    public func closeTransmission() {
        transportLayerObject.closeTransmission()
        messageInTransmission = nil
        isMessageInTransmission = false
        transmissionTimer?.invalidate()
        transmissionTimer = nil
        recentNotificationInfo = nil
        cachedMessagePairs = [:]
    }
    
    // MARK: Private Methods
    
    fileprivate func initiateSending() {
        isMessageInTransmission = true
        transmissionTimer?.invalidate()
        transmissionTimer = nil
        recentNotificationInfo = nil
        
        if messageInTransmission.type == .confirmable && !disableRetransmissions {
            retransmissionCounter = 0
            currentTransmitWait = 0
            sendWithRentransmissionHandling()
        }
        else {
            sendPendingMessage()
        }
    }
    
    //Actually PRIVATE! Do not call from outside. Has to be internally visible as NSTimer won't find it otherwise
    
    @objc func sendWithRentransmissionHandling() {
        sendPendingMessage()
        
        if retransmissionCounter < SCMessage.kMaxRetransmit {
            let timeout = SCMessage.kAckTimeout * pow(2.0, Double(retransmissionCounter)) * (SCMessage.kAckRandomFactor - ((Double(arc4random()) / Double(UINT32_MAX)).truncatingRemainder(dividingBy: 0.5)));
            currentTransmitWait += timeout
            transmissionTimer = Timer(timeInterval: timeout, target: self, selector: #selector(SCClient.sendWithRentransmissionHandling), userInfo: nil, repeats: false)
            retransmissionCounter += 1
        }
        else {
            transmissionTimer = Timer(timeInterval: SCMessage.kMaxTransmitWait - currentTransmitWait, target: self, selector: #selector(SCClient.notifyNoResponseExpected), userInfo: nil, repeats: false)
        }
        RunLoop.current.add(transmissionTimer, forMode: RunLoop.Mode.common)
    }
    
    //Actually PRIVATE! Do not call from outside. Has to be internally visible as NSTimer won't find it otherwise
    
    @objc func notifyNoResponseExpected() {
        closeTransmission()
        notifyDelegateWithErrorCode(.noResponseExpectedError)
    }
    
    fileprivate func sendPendingMessage() {
        if let data = messageInTransmission.toData() {
            sendCoAPMessageOverTransportLayerWithData(data as Data, endpoint: messageInTransmission.endpoint!, notifyDelegateAfterSuccess: true)
        }
        else {
            closeTransmission()
            notifyDelegateWithErrorCode(.messageInvalidForSendingError)
        }
    }
    
    fileprivate func sendEmptyMessageWithType(_ type: SCType, messageId: UInt16, toEndpoint endpoint: NWEndpoint) {
        let emptyMessage = SCMessage()
        emptyMessage.type = type;
        emptyMessage.messageId = messageId
        if let messageData = emptyMessage.toData() {
            sendCoAPMessageOverTransportLayerWithData(messageData as Data, endpoint: endpoint)
        }
    }
    
    fileprivate func sendCoAPMessageOverTransportLayerWithData(_ data: Data, endpoint: NWEndpoint, notifyDelegateAfterSuccess: Bool = false) {
        do {
            try transportLayerObject.sendCoAPData(data, toEndpoint: endpoint)
            if notifyDelegateAfterSuccess {
                delegate?.swiftCoapClient(self, didSendMessage: messageInTransmission, number: retransmissionCounter + 1)
            }
        }
        catch SCCoAPTransportLayerError.sendError(let errorDescription) {
            notifyDelegateWithTransportLayerErrorDescription(errorDescription)
        }
        catch SCCoAPTransportLayerError.setupError(let errorDescription) {
            notifyDelegateWithTransportLayerErrorDescription(errorDescription)
        }
        catch {}
    }
    
    fileprivate func notifyDelegateWithTransportLayerErrorDescription(_ errorDescription: String) {
        delegate?.swiftCoapClient(self, didFailWithError: NSError(domain: SCMessage.kCoapErrorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey : errorDescription]))
    }
    
    fileprivate func notifyDelegateWithErrorCode(_ clientErrorCode: SCClientErrorCode) {
        delegate?.swiftCoapClient(self, didFailWithError: NSError(domain: SCMessage.kCoapErrorDomain, code: clientErrorCode.rawValue, userInfo: [NSLocalizedDescriptionKey : clientErrorCode.descriptionString()]))
    }
    
    fileprivate func handleBlock2WithMessage(_ message: SCMessage) {
        if let block2opt = message.options[SCOption.block2.rawValue], let blockData = block2opt.first {
            let actualValue = UInt.fromData(blockData)
            if actualValue & 8 == 8 {
                //more bit is set, request next block
                let blockMessage = SCMessage(code: messageInTransmission.code, type: messageInTransmission.type, payload: messageInTransmission.payload)
                blockMessage.options = messageInTransmission.options
                let newValue = (actualValue & ~8) + 16
                var byteArray = newValue.toByteArray()
                blockMessage.options[SCOption.block2.rawValue] = [Data(bytes: &byteArray, count: byteArray.count)]
                sendCoAPMessage(blockMessage, endpoint: messageInTransmission.endpoint!)
            }
            else {
                isMessageInTransmission = false
            }
        }
    }
    
    fileprivate func continueBlock1ForBlockNumber(_ block: Int, szx: UInt) {
        let byteSize = pow(2, Double(szx) + 4)
        let blocksCount = ceil(Double(messageInTransmission.blockBody!.count) / byteSize)
        if block < Int(blocksCount) {
            var nextBlockLength: Int
            var blockValue: UInt = (UInt(block) << 4) + UInt(szx)
            
            if block < Int(blocksCount - 1) {
                nextBlockLength = Int(byteSize)
                blockValue += 8
            }
            else {
                nextBlockLength = messageInTransmission.blockBody!.count - Int(byteSize) * block
            }
            
            let startPos = Int(byteSize) * block
            sendBlock1MessageForCurrentContext(payload: messageInTransmission.blockBody!.subdata(in: (startPos ..< startPos + nextBlockLength)), blockValue: blockValue)
        }
    }
    
    fileprivate func sendBlock1MessageForCurrentContext(payload: Data, blockValue: UInt) {
        let blockMessage = SCMessage(code: messageInTransmission.code, type: messageInTransmission.type, payload: payload)
        blockMessage.options = messageInTransmission.options
        blockMessage.blockBody = messageInTransmission.blockBody
        var byteArray = blockValue.toByteArray()
        blockMessage.options[SCOption.block1.rawValue] = [Data(bytes: &byteArray, count: byteArray.count)]
        
        sendCoAPMessage(blockMessage, endpoint: messageInTransmission.endpoint!)
    }
    
    fileprivate func sendHttpMessageFromCoAPMessage(_ message: SCMessage) {
        guard let endpoint = message.endpoint, let hostPort = endpointToHostPort(endpoint) else {
            os_log(.error, "Can't call 'sendHttpMessageFromCoAPMessage' with endpoint %@", message.endpoint?.debugDescription ?? "NO ENDPOINT")
            return
        }
        let urlRequest = message.toHttpUrlRequestWithUrl()
        let urlString = "http://\(httpProxyingData!.hostName):\(httpProxyingData!.port)/\(hostPort.host):\(hostPort.port)"
        urlRequest.url = URL(string: urlString)
        urlRequest.timeoutInterval = SCMessage.kMaxTransmitWait
        urlRequest.cachePolicy = .useProtocolCachePolicy

        URLSession.shared.dataTask(with: urlRequest as URLRequest) { (data, response, error) -> Void in
            if error != nil {
                self.notifyDelegateWithErrorCode(.proxyingError)
            }
            else {
                let coapResponse = SCMessage.fromHttpUrlResponse(response as! HTTPURLResponse, data: data)
                coapResponse.timeStamp = Date()
                
                if self.cachingActive && self.messageInTransmission.code == SCCodeValue(classValue: 0, detailValue: 01) {
                    self.cachedMessagePairs[self.messageInTransmission] = SCMessage.copyFromMessage(coapResponse)
                }
                
                self.delegate?.swiftCoapClient(self, didReceiveMessage: coapResponse)
                self.handleBlock2WithMessage(coapResponse)
            }
        }
    }

    fileprivate func endpointToHostPort(_ endpoint: NWEndpoint) -> (host: String, port: UInt16)? {
        switch endpoint {
        case .hostPort(host: let host, port: let port):
            let port = port.rawValue
            switch host {
            case .name(let name, _):
                return (host: name, port: port)
            case .ipv4(let ip):
                return (host: ip.debugDescription, port: port)
            case .ipv6(let ip):
                return (host: ip.debugDescription, port: port)
            @unknown default:
                return nil
            }
        case .service(name: _, type: _, domain: _, interface: _),
             .unix(path:_),
             .url(_):
            return nil
        @unknown default:
            return nil
        }
    }
}


// MARK:
// MARK: SC Client Extension
// MARK: SC CoAP Transport Layer Delegate

extension SCClient: SCCoAPTransportLayerDelegate {
    public func transportLayerObject(_ transportLayerObject: SCCoAPTransportLayerProtocol, didReceiveData data: Data, fromEndpoint endpoint: NWEndpoint) {
        if let message = SCMessage.fromData(data) {

            //Check for spam
            if message.messageId != messageInTransmission.messageId && message.token != messageInTransmission.token {
                if message.type.rawValue <= SCType.nonConfirmable.rawValue {
                    sendEmptyMessageWithType(.reset, messageId: message.messageId, toEndpoint: endpoint)
                }
                return
            }

            //Invalidate Timer
            transmissionTimer?.invalidate()
            transmissionTimer = nil
            
            //Set timestamp
            message.timeStamp = Date()
            
            //Set return address
            message.endpoint = endpoint
            
            //Handle Caching, Separate, etc
            if cachingActive && messageInTransmission.code == SCCodeValue(classValue: 0, detailValue: 01) {
                cachedMessagePairs[messageInTransmission] = SCMessage.copyFromMessage(message)
            }
            
            //Handle Observe-Option (Observe Draft Section 3.4)
            if let observeValueArray = message.options[SCOption.observe.rawValue], let observeValue = observeValueArray.first {
                let currentNumber  = UInt.fromData(observeValue)
                if recentNotificationInfo == nil ||
                    (recentNotificationInfo.1 < currentNumber && currentNumber - recentNotificationInfo.1 < kMaxObserveOptionValue) ||
                    (recentNotificationInfo.1 > currentNumber && recentNotificationInfo.1 - currentNumber > kMaxObserveOptionValue) ||
                    (recentNotificationInfo.0 .compare(message.timeStamp!.addingTimeInterval(128)) == .orderedAscending) {
                    recentNotificationInfo = (message.timeStamp!, currentNumber)
                }
                else {
                    return
                }
            }
            
            //Notify Delegate
            delegate?.swiftCoapClient(self, didReceiveMessage: message)
            
            //Handle Block2
            handleBlock2WithMessage(message)
            
            //Handle Block1
            if message.code.toCodeSample() == SCCodeSample.continue, let block1opt = message.options[SCOption.block1.rawValue], let blockData = block1opt.first {
                var actualValue = UInt.fromData(blockData)
                let serverSZX = actualValue & 0b111
                actualValue >>= 4
                if serverSZX <= 6 {
                    var blockOffset = 1
                    if serverSZX < autoBlock1SZX! {
                        blockOffset = Int(pow(2, Double(autoBlock1SZX! - serverSZX)))
                        autoBlock1SZX = serverSZX
                    }
                    continueBlock1ForBlockNumber(Int(actualValue) + blockOffset, szx: serverSZX)
                }
            }
            
            //Further Operations
            if message.type == .confirmable {
                sendEmptyMessageWithType(.acknowledgement, messageId: message.messageId, toEndpoint: endpoint)
            }
            
            if (message.type != .acknowledgement || message.code.toCodeSample() != .empty) && message.options[SCOption.block2.rawValue] == nil && message.code.toCodeSample() != SCCodeSample.continue {
                isMessageInTransmission = false
            }
        }
        else {
            notifyDelegateWithErrorCode(.receivedInvalidMessageError)
        }
    }
    
    public func transportLayerObject(_ transportLayerObject: SCCoAPTransportLayerProtocol, didFailWithError error: NSError) {
        notifyDelegateWithErrorCode(.transportLayerSendError)
        transmissionTimer?.invalidate()
        transmissionTimer = nil
    }
}
