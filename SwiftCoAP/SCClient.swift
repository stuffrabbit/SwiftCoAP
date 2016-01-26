//
//  SCClient.swift
//  SwiftCoAP
//
//  Created by Wojtek Kordylewski on 03.05.15.
//  Copyright (c) 2015 Wojtek Kordylewski. All rights reserved.
//

import UIKit

//MARK:
//MARK: SC Client Delegate Protocol declaration

@objc protocol SCClientDelegate {
    
    //Tells the delegate that a valid CoAP message was received
    func swiftCoapClient(client: SCClient, didReceiveMessage message: SCMessage)
    
    //Tells the delegate that an error occured during or before transmission (refer to the "SCClientErrorCode" Enum)
    optional func swiftCoapClient(client: SCClient, didFailWithError error: NSError)
    
    //Tells the delegate that the respective message was sent. The property "number" indicates the amount of (re-)transmission attempts
    optional func swiftCoapClient(client: SCClient, didSendMessage message: SCMessage, number: Int)
}


//MARK:
//MARK: SC Client Error Code Enumeration

enum SCClientErrorCode: Int {
    case TransportLayerSendError, MessageInvalidForSendingError, ReceivedInvalidMessageError, NoResponseExpectedError, ProxyingError
    
    func descriptionString() -> String {
        switch self {
        case .TransportLayerSendError:
            return "Failed to send data via the given Transport Layer"
        case .MessageInvalidForSendingError:
            return "CoAP-Message is not valid"
        case .ReceivedInvalidMessageError:
            return "Data received was not a valid CoAP Message"
        case .NoResponseExpectedError:
            return "The recipient does not respond"
        case .ProxyingError:
            return "HTTP-URL Request could not be sent"
        }
    }
}


//MARK:
//MARK: SC Client IMPLEMENTATION

class SCClient: NSObject {
    
    //MARK: Constants and Properties
    
    //CONSTANTS
    let kMaxObserveOptionValue: UInt = 8388608
    
    //INTERNAL PROPERTIES (allowed to modify)
    
    weak var delegate: SCClientDelegate?
    var sendToken = true   //If true, a token with 4-8 Bytes is sent
    var autoBlock1SZX: UInt? = 2 { didSet { if let newValue = autoBlock1SZX { autoBlock1SZX = min(6, newValue) } } } //If not nil, Block1 transfer will be used automatically when the payload size exceeds the value 2^(autoBlock1SZX + 4). Valid Values: 0-6.
    
    var httpProxyingData: (hostName: String, port: UInt16)?     //If not nil, all messages will be sent via http to the given proxy address
    var cachingActive = false   //Activates caching
    var disableRetransmissions = false
    
    //READ-ONLY PROPERTIES
    
    private (set) var isMessageInTransmission = false   //Indicates whether a message is in transmission and/or responses are still expected (e.g. separate, block, observe)
    
    //PRIVATE PROPERTIES
    
    private var transportLayerObject: SCCoAPTransportLayerProtocol!
    private var transmissionTimer: NSTimer!
    private var messageInTransmission: SCMessage!
    private var currentMessageId: UInt16 = UInt16(arc4random_uniform(0xFFFF) &+ 1)
    private var retransmissionCounter = 0
    private var currentTransmitWait = 0.0
    private var recentNotificationInfo: (NSDate, UInt)!
    lazy private var cachedMessagePairs = [SCMessage : SCMessage]()
    
    
    //MARK: Internal Methods (allowed to use)
    
    init(delegate: SCClientDelegate?, transportLayerObject: SCCoAPTransportLayerProtocol = SCCoAPUDPTransportLayer()) {
        self.delegate = delegate
        super.init()
        self.transportLayerObject = transportLayerObject
        self.transportLayerObject.transportLayerDelegate = self
    }
    
    func sendCoAPMessage(message: SCMessage, hostName: String, port: UInt16) {
        currentMessageId = (currentMessageId % 0xFFFF) + 1
        
        message.hostName = hostName
        message.port = port
        message.messageId = currentMessageId
        message.timeStamp = NSDate()
        
        messageInTransmission = message
        
        if sendToken {
            message.token = UInt64(arc4random_uniform(0xFFFFFFFF) + 1) + (UInt64(arc4random_uniform(0xFFFFFFFF) + 1) << 32)
        }
        
        if cachingActive && message.code == SCCodeValue(classValue: 0, detailValue: 01) {
            for cachedMessage in cachedMessagePairs.keys {
                if cachedMessage.equalForCachingWithMessage(message) {
                    if cachedMessage.isFresh() {
                        if message.options[SCOption.Observe.rawValue] == nil { cachedMessage.options[SCOption.Observe.rawValue] = nil }
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
            if message.blockBody == nil && autoBlock1SZX != nil {
                let fixedByteSize = pow(2, Double(autoBlock1SZX!) + 4)
                if let payload = message.payload {
                    let blocksCount = ceil(Double(payload.length) / fixedByteSize)
                    if blocksCount > 1 {
                        message.blockBody = payload
                        let blockValue = 8 + UInt(autoBlock1SZX!)
                        
                        sendBlock1MessageForCurrentContext(payload: payload.subdataWithRange(NSMakeRange(0, Int(fixedByteSize))), blockValue: blockValue)
                        return
                    }
                }
            }
            
            initiateSending()
        }
    }
    
    
    // Cancels observe directly, sending the previous message with an Observe-Option Value of 1. Only effective, if the previous message initiated a registration as observer with the respective server. To cancel observer indirectly (forget about the current state) call "closeTransmission()" or send another Message (this cleans up the old state automatically)
    func cancelObserve() {
        let cancelMessage = SCMessage(code: SCCodeValue(classValue: 0, detailValue: 01)!, type: .NonConfirmable, payload: nil)
        cancelMessage.token = messageInTransmission.token
        cancelMessage.options = messageInTransmission.options
        currentMessageId = (currentMessageId % 0xFFFF) + 1
        cancelMessage.messageId = currentMessageId
        cancelMessage.hostName = messageInTransmission.hostName
        cancelMessage.port = messageInTransmission.port
        var cancelByte: UInt8 = 1
        cancelMessage.options[SCOption.Observe.rawValue] = [NSData(bytes: &cancelByte, length: 1)]
        if let messageData = cancelMessage.toData() {
            sendCoAPMessageOverTransportLayerWithData(messageData, host: messageInTransmission.hostName!, port: messageInTransmission.port!)
        }
    }
    
    
    //Closes the transmission. It is recommended to call this method anytime you do not expect to receive a response any longer.
    
    func closeTransmission() {
        transportLayerObject.closeTransmission()
        messageInTransmission = nil
        isMessageInTransmission = false
        transmissionTimer?.invalidate()
        transmissionTimer = nil
        recentNotificationInfo = nil
        cachedMessagePairs = [:]
    }
    
    // MARK: Private Methods
    
    private func initiateSending() {
        isMessageInTransmission = true
        transmissionTimer?.invalidate()
        transmissionTimer = nil
        recentNotificationInfo = nil
        
        if messageInTransmission.type == .Confirmable && !disableRetransmissions {
            retransmissionCounter = 0
            currentTransmitWait = 0
            sendWithRentransmissionHandling()
        }
        else {
            sendPendingMessage()
        }
    }
    
    //Actually PRIVATE! Do not call from outside. Has to be internally visible as NSTimer won't find it otherwise
    
    func sendWithRentransmissionHandling() {
        sendPendingMessage()
        
        if retransmissionCounter < SCMessage.kMaxRetransmit {
            let timeout = SCMessage.kAckTimeout * pow(2.0, Double(retransmissionCounter)) * (SCMessage.kAckRandomFactor - (Double(arc4random()) / Double(UINT32_MAX) % 0.5));
            currentTransmitWait += timeout
            transmissionTimer = NSTimer(timeInterval: timeout, target: self, selector: "sendWithRentransmissionHandling", userInfo: nil, repeats: false)
            retransmissionCounter++
        }
        else {
            transmissionTimer = NSTimer(timeInterval: SCMessage.kMaxTransmitWait - currentTransmitWait, target: self, selector: "notifyNoResponseExpected", userInfo: nil, repeats: false)
        }
        NSRunLoop.currentRunLoop().addTimer(transmissionTimer, forMode: NSRunLoopCommonModes)
    }
    
    //Actually PRIVATE! Do not call from outside. Has to be internally visible as NSTimer won't find it otherwise
    
    func notifyNoResponseExpected() {
        closeTransmission()
        notifyDelegateWithErrorCode(.NoResponseExpectedError)
    }
    
    private func sendPendingMessage() {
        if let data = messageInTransmission.toData() {
            sendCoAPMessageOverTransportLayerWithData(data, host: messageInTransmission.hostName!, port: messageInTransmission.port!, notifyDelegateAfterSuccess: true)
        }
        else {
            closeTransmission()
            notifyDelegateWithErrorCode(.MessageInvalidForSendingError)
        }
    }
    
    private func sendEmptyMessageWithType(type: SCType, messageId: UInt16, toHost host: String, port: UInt16) {
        let emptyMessage = SCMessage()
        emptyMessage.type = type;
        emptyMessage.messageId = messageId
        if let messageData = emptyMessage.toData() {
            sendCoAPMessageOverTransportLayerWithData(messageData, host: host, port: port)
        }
    }
    
    private func sendCoAPMessageOverTransportLayerWithData(data: NSData, host: String, port: UInt16, notifyDelegateAfterSuccess: Bool = false) {
        do {
            try transportLayerObject.sendCoAPData(data, toHost: host, port: port)
            if notifyDelegateAfterSuccess {
                delegate?.swiftCoapClient?(self, didSendMessage: messageInTransmission, number: retransmissionCounter + 1)
            }
        }
        catch SCCoAPTransportLayerError.SendError(let errorDescription) {
            notifyDelegateWithTransportLayerErrorDescription(errorDescription)
        }
        catch SCCoAPTransportLayerError.SetupError(let errorDescription) {
            notifyDelegateWithTransportLayerErrorDescription(errorDescription)
        }
        catch {}
    }
    
    private func notifyDelegateWithTransportLayerErrorDescription(errorDescription: String) {
        delegate?.swiftCoapClient?(self, didFailWithError: NSError(domain: SCMessage.kCoapErrorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey : errorDescription]))
    }
    
    private func notifyDelegateWithErrorCode(clientErrorCode: SCClientErrorCode) {
        delegate?.swiftCoapClient?(self, didFailWithError: NSError(domain: SCMessage.kCoapErrorDomain, code: clientErrorCode.rawValue, userInfo: [NSLocalizedDescriptionKey : clientErrorCode.descriptionString()]))
    }
    
    private func handleBlock2WithMessage(message: SCMessage) {
        if let block2opt = message.options[SCOption.Block2.rawValue], blockData = block2opt.first {
            let actualValue = UInt.fromData(blockData)
            if actualValue & 8 == 8 {
                //more bit is set, request next block
                let blockMessage = SCMessage(code: messageInTransmission.code, type: messageInTransmission.type, payload: messageInTransmission.payload)
                blockMessage.options = messageInTransmission.options
                let newValue = (actualValue & ~8) + 16
                var byteArray = newValue.toByteArray()
                blockMessage.options[SCOption.Block2.rawValue] = [NSData(bytes: &byteArray, length: byteArray.count)]
                sendCoAPMessage(blockMessage, hostName: messageInTransmission.hostName!, port: messageInTransmission.port!)
            }
            else {
                isMessageInTransmission = false
            }
        }
    }
    
    private func continueBlock1ForBlockNumber(block: Int, szx: UInt) {
        let byteSize = pow(2, Double(szx) + 4)
        let blocksCount = ceil(Double(messageInTransmission.blockBody!.length) / byteSize)
        if block < Int(blocksCount) {
            var nextBlockLength: Int
            var blockValue: UInt = (UInt(block) << 4) + UInt(szx)
            
            if block < Int(blocksCount - 1) {
                nextBlockLength = Int(byteSize)
                blockValue += 8
            }
            else {
                nextBlockLength = messageInTransmission.blockBody!.length - Int(byteSize) * block
            }
            
            sendBlock1MessageForCurrentContext(payload: messageInTransmission.blockBody!.subdataWithRange(NSMakeRange(Int(byteSize) * block, nextBlockLength)), blockValue: blockValue)
        }
    }
    
    private func sendBlock1MessageForCurrentContext(payload payload: NSData, blockValue: UInt) {
        let blockMessage = SCMessage(code: messageInTransmission.code, type: messageInTransmission.type, payload: payload)
        blockMessage.options = messageInTransmission.options
        blockMessage.blockBody = messageInTransmission.blockBody
        var byteArray = blockValue.toByteArray()
        blockMessage.options[SCOption.Block1.rawValue] = [NSData(bytes: &byteArray, length: byteArray.count)]
        
        sendCoAPMessage(blockMessage, hostName: messageInTransmission.hostName!, port: messageInTransmission.port!)
    }
    
    private func sendHttpMessageFromCoAPMessage(message: SCMessage) {
        let urlRequest = message.toHttpUrlRequestWithUrl()
        let urlString = "http://\(httpProxyingData!.hostName):\(httpProxyingData!.port)/\(message.hostName!):\(message.port!)"
        urlRequest.URL = NSURL(string: urlString)
        urlRequest.timeoutInterval = SCMessage.kMaxTransmitWait
        urlRequest.cachePolicy = .UseProtocolCachePolicy
        
        NSURLConnection.sendAsynchronousRequest(urlRequest, queue: NSOperationQueue.mainQueue()) { (response, data, error) -> Void in
            if error != nil {
                self.notifyDelegateWithErrorCode(.ProxyingError)
            }
            else {
                let coapResponse = SCMessage.fromHttpUrlResponse(response as! NSHTTPURLResponse, data: data)
                coapResponse.timeStamp = NSDate()
                
                if self.cachingActive && self.messageInTransmission.code == SCCodeValue(classValue: 0, detailValue: 01) {
                    self.cachedMessagePairs[self.messageInTransmission] = SCMessage.copyFromMessage(coapResponse)
                }
                
                self.delegate?.swiftCoapClient(self, didReceiveMessage: coapResponse)
                self.handleBlock2WithMessage(coapResponse)
            }
        }
    }
}


// MARK:
// MARK: SC Client Extension
// MARK: SC CoAP Transport Layer Delegate

extension SCClient: SCCoAPTransportLayerDelegate {
    func transportLayerObject(transportLayerObject: SCCoAPTransportLayerProtocol, didReceiveData data: NSData, fromHost host: String, port: UInt16) {
        if let message = SCMessage.fromData(data) {
    
            //Check for spam
            if message.messageId != messageInTransmission.messageId && message.token != messageInTransmission.token {
                if message.type.rawValue <= SCType.NonConfirmable.rawValue {
                    sendEmptyMessageWithType(.Reset, messageId: message.messageId, toHost: host, port: port)
                }
                return
            }
    
            //Invalidate Timer
            transmissionTimer?.invalidate()
            transmissionTimer = nil
            
            //Set timestamp
            message.timeStamp = NSDate()
            
            //Handle Caching, Separate, etc
            if cachingActive && messageInTransmission.code == SCCodeValue(classValue: 0, detailValue: 01) {
                cachedMessagePairs[messageInTransmission] = SCMessage.copyFromMessage(message)
            }
            
            //Handle Observe-Option (Observe Draft Section 3.4)
            if let observeValueArray = message.options[SCOption.Observe.rawValue], observeValue = observeValueArray.first {
                let currentNumber  = UInt.fromData(observeValue)
                if recentNotificationInfo == nil ||
                    (recentNotificationInfo.1 < currentNumber && currentNumber - recentNotificationInfo.1 < kMaxObserveOptionValue) ||
                    (recentNotificationInfo.1 > currentNumber && recentNotificationInfo.1 - currentNumber > kMaxObserveOptionValue) ||
                    (recentNotificationInfo.0 .compare(message.timeStamp!.dateByAddingTimeInterval(128)) == .OrderedAscending) {
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
            if message.code.toCodeSample() == SCCodeSample.Continue, let block1opt = message.options[SCOption.Block1.rawValue], blockData = block1opt.first {
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
            if message.type == .Confirmable {
                sendEmptyMessageWithType(.Acknowledgement, messageId: message.messageId, toHost: host, port: port)
            }
            
            if (message.type != .Acknowledgement || message.code.toCodeSample() != .Empty) && message.options[SCOption.Block2.rawValue] == nil && message.code.toCodeSample() != SCCodeSample.Continue {
                isMessageInTransmission = false
            }
        }
        else {
            notifyDelegateWithErrorCode(.ReceivedInvalidMessageError)
        }
    }
    
    func transportLayerObject(transportLayerObject: SCCoAPTransportLayerProtocol, didFailWithError error: NSError) {
        notifyDelegateWithErrorCode(.TransportLayerSendError)
        transmissionTimer?.invalidate()
        transmissionTimer = nil
    }
}