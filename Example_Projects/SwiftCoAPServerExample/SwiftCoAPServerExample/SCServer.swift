//
//  SCServer.swift
//  SwiftCoAP
//
//  Created by Wojtek Kordylewski on 03.06.15.
//  Copyright (c) 2015 Wojtek Kordylewski. All rights reserved.
//

import UIKit

protocol SCServerDelegate {
    func swiftCoapServer(server: SCServer, didFailWithError error: NSError)
    func swiftCoapServer(server: SCServer, didHandleRequestWithCode code: SCCodeValue, forResource resource: SCResourceModel)
    func swiftCoapServer(server: SCServer, didRejectRequestWithCode requestCode: SCCodeValue, forPath path: String, withResponseCode responseCode: SCCodeValue)
    func swiftCoapServer(server: SCServer, didSendSeparateResponseMessage: SCMessage, number: Int)
}

enum SCAllowedRoute: UInt {
    case Get = 0b1
    case Post = 0b10
    case Put = 0b100
    case Delete = 0b1000
}

enum SCServerErrorCode: Int {
    case UdpSocketSendError, ReceivedInvalidMessageError, NoResponseExpectedError
    
    func descriptionString() -> String {
        switch self {
        case .UdpSocketSendError:
            return "Failed to send data via UDP"
        case .ReceivedInvalidMessageError:
            return "Data received was not a valid CoAP Message"
        case .NoResponseExpectedError:
            return "The recipient does not respond"
        }
    }
}

class SCServer: NSObject {
    let kCoapErrorDomain = "SwiftCoapErrorDomain"
    let kAckTimeout = 2.0
    let kAckRandomFactor = 1.5
    let kMaxRetransmit = 4
    let kMaxTransmitWait = 93.0
    
    var delegate: SCServerDelegate?
    
    private var currentRequestMessages: [SCMessage]!
    private let port: UInt16
    private var udpSocket: GCDAsyncUdpSocket!
    private var udpSocketTag: Int = 0
    private lazy var pendingMessagesForEndpoints = [NSData : [(SCMessage, NSTimer?)]]()
    private lazy var registeredObserverForResource = [SCResourceModel : [(UInt64, NSData, UInt)]]()

    lazy var resources = [SCResourceModel]()

    init?(port: UInt16) {
        self.port = port
        super.init()
        
        if !setUpUdpSocket() {
            return nil
        }
    }
    
    func didCompleteAsynchronousRequestForOriginalMessage(message: SCMessage, resource: SCResourceModel, values:(statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!)) {
        var type: SCType = message.type == .Confirmable ? .Confirmable : .NonConfirmable
        var separateMessage = createMessageForValues((values.statusCode, values.payloadData, values.contentFormat, nil), withType: type, relatedMessage: message, requestedResource: resource)
        separateMessage.messageId = UInt16(arc4random_uniform(0xFFFF) &+ 1)
        setupReliableTransmissionOfMessage(separateMessage, forResource: resource)
    }
    
    func updateRegisteredObserversForResource(resource: SCResourceModel) {
        if var valueArray = registeredObserverForResource[resource] {
            for var i = 0; i < valueArray.count; i++ {
                let (token, address, sequenceNumber) = valueArray[i]
                var notification = SCMessage(code: SCCodeValue(classValue: 2, detailValue: 05), type: .Confirmable, payload: resource.observableData)
                notification.token = token
                notification.messageId = UInt16(arc4random_uniform(0xFFFF) &+ 1)
                notification.addressData = address
                var newSequenceNumber = (sequenceNumber + 1) % UInt(pow(2.0, 24))
                var byteArray = newSequenceNumber.toByteArray()
                notification.addOption(SCOption.Observe.rawValue, data: NSData(bytes: &byteArray, length: byteArray.count))
                valueArray[i] = (token, address, newSequenceNumber)
                registeredObserverForResource[resource] = valueArray
                setupReliableTransmissionOfMessage(notification, forResource: resource)
            }
        }
    }

    
    // MARK: Private Methods

    private func setUpUdpSocket() -> Bool {
        udpSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: dispatch_get_main_queue())
        
        var error: NSError?
        if !udpSocket!.bindToPort(5683, error: &error) {
            return false
        }
        
        if !udpSocket!.beginReceiving(&error) {
            return false
        }
        return true
    }
    
    private func setupReliableTransmissionOfMessage(message: SCMessage, forResource resource: SCResourceModel) {
        if let addressData = message.addressData {
            var timer: NSTimer!
            if message.type == .Confirmable {
                message.resourceForConfirmableResponse = resource
                var timeout = kAckTimeout * 2.0 * (kAckRandomFactor - (Double(arc4random()) / Double(UINT32_MAX) % 0.5));
                timer = NSTimer(timeInterval: timeout, target: self, selector: Selector("handleRetransmission:"), userInfo: ["retransmissionCount" : 1, "totalTime" : timeout, "message" : message, "resource" : resource], repeats: false)
                NSRunLoop.currentRunLoop().addTimer(timer, forMode: NSRunLoopCommonModes)
            }
            sendMessage(message)
            
            if var contextArray = pendingMessagesForEndpoints[addressData] {
                contextArray.append((message, timer))
                pendingMessagesForEndpoints[addressData] = contextArray
            }
            else {
                pendingMessagesForEndpoints[addressData] = [(message, timer)]
            }
        }
    }
    
    private func sendMessageWithType(type: SCType, code: SCCodeValue, payload: NSData?, messageId: UInt16, addressData: NSData, token: UInt64 = 0) {
        let emptyMessage = SCMessage(code: code, type: type, payload: payload)
        emptyMessage.messageId = messageId
        emptyMessage.token = token
        emptyMessage.addressData = addressData
        sendMessage(emptyMessage)
    }
    
    private func sendMessage(message: SCMessage) {
        udpSocket?.sendData(message.toData()!, toAddress: message.addressData, withTimeout: 0, tag: udpSocketTag)
        udpSocketTag = (udpSocketTag % Int.max) + 1
    }
    
    
    //Actually PRIVATE! Do not call from outside. Has to be internally visible as NSTimer won't find it otherwise
    
    func handleRetransmission(timer: NSTimer) {
        var retransmissionCount = timer.userInfo!["retransmissionCount"] as! Int
        var totalTime = timer.userInfo!["totalTime"] as! Double
        var message = timer.userInfo!["message"] as! SCMessage
        var resource = timer.userInfo!["resource"] as! SCResourceModel
        sendMessage(message)
        delegate?.swiftCoapServer(self, didSendSeparateResponseMessage: message, number: retransmissionCount)
        
        if let addressData = message.addressData, var contextArray = pendingMessagesForEndpoints[addressData] {
            let nextTimer: NSTimer
            if retransmissionCount < kMaxRetransmit {
                var timeout = kAckTimeout * pow(2.0, Double(retransmissionCount)) * (kAckRandomFactor - (Double(arc4random()) / Double(UINT32_MAX) % 0.5));
                nextTimer = NSTimer(timeInterval: timeout, target: self, selector: Selector("handleRetransmission:"), userInfo: ["retransmissionCount" : retransmissionCount + 1, "totalTime" : totalTime + timeout, "message" : message, "resource" : resource], repeats: false)
            }
            else {
                nextTimer = NSTimer(timeInterval: kMaxTransmitWait - totalTime, target: self, selector: Selector("notifyNoResponseExpected:"), userInfo: ["message" : message, "resource" : resource], repeats: false)
            }
            NSRunLoop.currentRunLoop().addTimer(nextTimer, forMode: NSRunLoopCommonModes)
            
            //Update context
            for var i = 0; i < contextArray.count; i++ {
                let tuple = contextArray[i]
                if tuple.0 == message {
                    contextArray[i] = (tuple.0, nextTimer)
                    pendingMessagesForEndpoints[addressData] = contextArray
                    break
                }
            }
        }
    }
    
    
    //Actually PRIVATE! Do not call from outside. Has to be internally visible as NSTimer won't find it otherwise
    
    func notifyNoResponseExpected(timer: NSTimer)  {
        var message = timer.userInfo!["message"] as! SCMessage
        var resource = timer.userInfo!["resource"] as! SCResourceModel

        removeContextForMessage(message)
        notifyDelegateWithErrorCode(.NoResponseExpectedError)

        if message.options[SCOption.Observe.rawValue] != nil, let address = message.addressData {
            deregisterObserveForResource(resource, address: address)
        }
    }
    
    private func removeContextForMessage(message: SCMessage) {
        if let addressData = message.addressData, var contextArray = pendingMessagesForEndpoints[addressData] {
           
            func removeFromContextAtIndex(index: Int) {
                contextArray.removeAtIndex(index)
                if contextArray.count > 0 {
                    pendingMessagesForEndpoints[addressData] = contextArray
                }
                else {
                    pendingMessagesForEndpoints.removeValueForKey(addressData)
                }
            }
            
            for var i = 0; i < contextArray.count; i++ {
                let tuple = contextArray[i]
                if tuple.0.messageId == message.messageId {
                    if let oldTimer = tuple.1 {
                        oldTimer.invalidate()
                    }
                    if message.type == .Reset && tuple.0.options[SCOption.Observe.rawValue] != nil, let resource = tuple.0.resourceForConfirmableResponse  {
                        deregisterObserveForResource(resource, address: addressData)
                    }
                    removeFromContextAtIndex(i)
                    break
                }
            }
        }
    }
    
    private func notifyDelegateWithErrorCode(clientErrorCode: SCServerErrorCode) {
        delegate?.swiftCoapServer(self, didFailWithError: NSError(domain: kCoapErrorDomain, code: clientErrorCode.rawValue, userInfo: [NSLocalizedDescriptionKey : clientErrorCode.descriptionString()]))
    }
    
    private func createMessageForValues(values: (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!, locationUri: String!), withType type: SCType, relatedMessage message: SCMessage, requestedResource resource: SCResourceModel) -> SCMessage {
        var responseMessage = SCMessage(code: values.statusCode, type: type, payload: values.payloadData)
        
        if values.contentFormat != nil {
            var contentFormatByteArray = values.contentFormat.rawValue.toByteArray()
            responseMessage.addOption(SCOption.ContentFormat.rawValue, data: NSData(bytes: &contentFormatByteArray, length: contentFormatByteArray.count))
        }
        
        if values.locationUri != nil {
            if let (pathDataArray, queryDataArray) = SCMessage.getPathAndQueryDataArrayFromUriString(values.locationUri) where pathDataArray.count > 0 {
                responseMessage.options[SCOption.LocationPath.rawValue] = pathDataArray
                if queryDataArray.count > 0 {
                    responseMessage.options[SCOption.LocationQuery.rawValue] = queryDataArray
                }
            }
        }
        
        if resource.maxAgeValue != nil {
            var byteArray = resource.maxAgeValue.toByteArray()
            responseMessage.addOption(SCOption.MaxAge.rawValue, data: NSData(bytes: &byteArray, length: byteArray.count))
        }
        
        if resource.etag != nil {
            responseMessage.addOption(SCOption.Etag.rawValue, data: resource.etag)
        }
        
        if resource.observableData != nil, let observeValueArray = message.options[SCOption.Observe.rawValue], observeValue = observeValueArray.first, msgAddr = message.addressData {
            if observeValue.length > 0 && UInt.fromData(observeValue) == 1 {
                deregisterObserveForResource(resource, address: msgAddr)
            }
            else {
                //Register for Observe
                var newValueArray: [(UInt64, NSData, UInt)]
                var currentSequenceNumber: UInt = 0
                if var valueArray = registeredObserverForResource[resource] {
                    if let index = getIndexOfObserverInValueArray(valueArray, address: msgAddr) {
                        let (_, _, sequenceNumber) = valueArray[index]
                        var newSequenceNumber = (sequenceNumber + 1) % UInt(pow(2.0, 24))
                        currentSequenceNumber = UInt(newSequenceNumber)
                        valueArray[index] = (message.token, msgAddr, newSequenceNumber)
                    }
                    else {
                        valueArray.append((message.token, msgAddr, 0))
                    }
                    newValueArray = valueArray
                }
                else {
                    newValueArray = [(message.token, msgAddr, 0)]
                }

                registeredObserverForResource[resource] = newValueArray
                var byteArray = currentSequenceNumber.toByteArray()
                responseMessage.addOption(SCOption.Observe.rawValue, data: NSData(bytes: &byteArray, length: byteArray.count))
            }
        }
        
        responseMessage.messageId = message.messageId
        responseMessage.token = message.token
        responseMessage.addressData = message.addressData
        
        return responseMessage
    }
    
    private func deregisterObserveForResource(resource: SCResourceModel, address: NSData) {
        if var valueArray = registeredObserverForResource[resource], let index = getIndexOfObserverInValueArray(valueArray, address: address) {
            valueArray.removeAtIndex(index)
            if valueArray.count == 0 {
                registeredObserverForResource.removeValueForKey(resource)
            }
            else {
                registeredObserverForResource[resource] = valueArray
            }
        }
    }
    
    private func getIndexOfObserverInValueArray(valueArray: [(UInt64, NSData, UInt)], address: NSData) -> Int? {
        for var i = 0; i < valueArray.count; i++ {
            let (_, add, _) = valueArray[i]
            if add == address {
                return i
            }
        }
        return nil
    }
}

extension SCServer: GCDAsyncUdpSocketDelegate {
    func udpSocket(sock: GCDAsyncUdpSocket!, didReceiveData data: NSData!, fromAddress address: NSData!, withFilterContext filterContext: AnyObject!) {
        if let message = SCMessage.fromData(data) {
            message.addressData = address

            //Filter
            
            var resultType: SCType
            switch message.type {
            case .Confirmable:
                resultType = .Acknowledgement
            case .NonConfirmable:
                resultType = .NonConfirmable
            default:
                removeContextForMessage(message)
                return
            }
            
            if message.code == SCCodeValue(classValue: 0, detailValue: 00) || message.code.classValue >= 1 {
                if message.type == .Confirmable || message.type == .NonConfirmable {
                    sendMessageWithType(.Reset, code: SCCodeValue(classValue: 0, detailValue: 00), payload: nil, messageId: message.messageId, addressData: address)
                }
                return
            }
            
            //URI-Path
            
            var resultResource: SCResourceModel!
            let completeUri =  message.completeUriPath()
            for resource in resources {
                if resource.name == completeUri {
                    resultResource = resource
                    break
                }
            }
            
            func respondMethodNotAllowed() {
                var responseCode = SCCodeSample.MethodNotAllowed.codeValue()
                sendMessageWithType(resultType, code: responseCode, payload: "Method Not Allowed".dataUsingEncoding(NSUTF8StringEncoding), messageId: message.messageId, addressData: address, token: message.token)
                delegate?.swiftCoapServer(self, didRejectRequestWithCode: message.code, forPath: message.completeUriPath(), withResponseCode: responseCode)
            }

            if resultResource != nil {
                var resultTuple: (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!, locationUri: String!)!
                
                switch message.code {
                case SCCodeValue(classValue: 0, detailValue: 01) where resultResource.allowedRoutes & SCAllowedRoute.Get.rawValue == SCAllowedRoute.Get.rawValue:
                    if resultResource.willHandleDataAsynchronouslyForGet(queryDictionary: message.uriQueryDictionary(), options: message.options, originalMessage: message) {
                        if message.type == .Confirmable {
                            sendMessageWithType(.Acknowledgement, code: SCCodeValue(classValue: 0, detailValue: 00), payload: nil, messageId: message.messageId, addressData: address)
                        }
                        delegate?.swiftCoapServer(self, didHandleRequestWithCode: message.code, forResource: resultResource)
                        return
                    }
                    else if let (statusCode, payloadData, contentFormat) = resultResource.dataForGet(queryDictionary: message.uriQueryDictionary(), options: message.options) {
                        resultTuple = (statusCode, payloadData, contentFormat, nil)
                    }
                case SCCodeValue(classValue: 0, detailValue: 02) where resultResource.allowedRoutes & SCAllowedRoute.Post.rawValue == SCAllowedRoute.Post.rawValue:
                    if let tuple = resultResource.dataForPost(queryDictionary: message.uriQueryDictionary(), options: message.options, requestData: message.payload) {
                        resultTuple = tuple
                    }
                case SCCodeValue(classValue: 0, detailValue: 03) where resultResource.allowedRoutes & SCAllowedRoute.Put.rawValue == SCAllowedRoute.Put.rawValue:
                    if let tuple = resultResource.dataForPut(queryDictionary: message.uriQueryDictionary(), options: message.options, requestData: message.payload) {
                        resultTuple = tuple
                    }
                case SCCodeValue(classValue: 0, detailValue: 04) where resultResource.allowedRoutes & SCAllowedRoute.Delete.rawValue == SCAllowedRoute.Delete.rawValue:
                    if let (statusCode, payloadData, contentFormat) = resultResource.dataForDelete(queryDictionary: message.uriQueryDictionary(), options: message.options) {
                        resultTuple = (statusCode, payloadData, contentFormat, nil)                        
                    }
                default:
                    respondMethodNotAllowed()
                    return
                }
                
                if resultTuple != nil {
                    var responseMessage = createMessageForValues(resultTuple, withType: resultType, relatedMessage: message, requestedResource: resultResource)
                    sendMessage(responseMessage)
                    delegate?.swiftCoapServer(self, didHandleRequestWithCode: message.code, forResource: resultResource)
                    //TODO Payload pruefen fuer Block2
                }
                else {
                    respondMethodNotAllowed()
                }
            }
            else {
                var responseCode = SCCodeValue(classValue: 4, detailValue: 04)
                sendMessageWithType(resultType, code: responseCode, payload: "Not Found".dataUsingEncoding(NSUTF8StringEncoding), messageId: message.messageId, addressData: address, token: message.token)
                delegate?.swiftCoapServer(self, didRejectRequestWithCode: message.code, forPath: message.completeUriPath(), withResponseCode: responseCode)
            }
        }
    }
    
    func udpSocket(sock: GCDAsyncUdpSocket!, didNotSendDataWithTag tag: Int, dueToError error: NSError!) {
        notifyDelegateWithErrorCode(.UdpSocketSendError)
    }
}
