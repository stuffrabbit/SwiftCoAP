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

protocol SCResourceModel {
    var name: String { get }
    var allowedRoutes: UInt { get }
    
    var maxAgeValue: UInt! { get set }
    var etag: NSData! { get set }

    
    func willHandleDataAsynchronouslyForGet(#queryDictionary: [String : String], options: [Int : [NSData]], originalMessage: SCMessage) -> Bool
    func dataForGet(#queryDictionary: [String : String], options: [Int : [NSData]]) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!)?
    func dataForPost(#queryDictionary: [String : String], options: [Int : [NSData]], requestData: NSData?) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!, locationUri: String!)?
    func dataForPut(#queryDictionary: [String : String], options: [Int : [NSData]], requestData: NSData?) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!, locationUri: String!)?
    func dataForDelete(#queryDictionary: [String : String], options: [Int : [NSData]]) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!)?
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
    private lazy var pendingMessagesForEndpoints = [NSData : (SCMessage, NSTimer?)]()

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
        if let addressData = separateMessage.addressData {
            if let tuple = pendingMessagesForEndpoints[addressData], oldTimer = tuple.1 where oldTimer.valid {
                oldTimer.invalidate()
            }
            
            var timer: NSTimer!
            if separateMessage.type == .Confirmable {
                var timeout = kAckTimeout * 2.0 * (kAckRandomFactor - (Double(arc4random()) / Double(UINT32_MAX) % 0.5));
                timer = NSTimer(timeInterval: timeout, target: self, selector: Selector("handleRetransmission:"), userInfo: ["retransmissionCount" : 1, "totalTime" : timeout, "message" : separateMessage], repeats: false)
                NSRunLoop.currentRunLoop().addTimer(timer, forMode: NSRunLoopCommonModes)
            }
            pendingMessagesForEndpoints[addressData] = (separateMessage, timer)
            sendMessage(separateMessage)
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
        
        sendMessage(message)
        delegate?.swiftCoapServer(self, didSendSeparateResponseMessage: message, number: retransmissionCount)
        
        if let addressData = message.addressData, tuple = pendingMessagesForEndpoints[addressData] {
            let nextTimer: NSTimer
            if retransmissionCount < kMaxRetransmit {
                var timeout = kAckTimeout * pow(2.0, Double(retransmissionCount)) * (kAckRandomFactor - (Double(arc4random()) / Double(UINT32_MAX) % 0.5));
                nextTimer = NSTimer(timeInterval: timeout, target: self, selector: Selector("handleRetransmission:"), userInfo: ["retransmissionCount" : retransmissionCount + 1, "totalTime" : totalTime + timeout, "message" : message], repeats: false)
            }
            else {
                nextTimer = NSTimer(timeInterval: kMaxTransmitWait - totalTime, target: self, selector: Selector("notifyNoResponseExpected:"), userInfo: ["message" : message], repeats: false)
            }
            NSRunLoop.currentRunLoop().addTimer(nextTimer, forMode: NSRunLoopCommonModes)
            pendingMessagesForEndpoints[addressData] = (tuple.0, nextTimer)
        }
    }
    
    
    //Actually PRIVATE! Do not call from outside. Has to be internally visible as NSTimer won't find it otherwise
    
    func notifyNoResponseExpected(timer: NSTimer)  {
        var message = timer.userInfo!["message"] as! SCMessage
        if let addressData = message.addressData, tuple = pendingMessagesForEndpoints[addressData] {
            pendingMessagesForEndpoints[addressData] = (tuple.0, nil)
        }
        notifyDelegateWithErrorCode(.NoResponseExpectedError)
    }
    
    private func notifyDelegateWithErrorCode(clientErrorCode: SCServerErrorCode) {
        delegate?.swiftCoapServer(self, didFailWithError: NSError(domain: kCoapErrorDomain, code: clientErrorCode.rawValue, userInfo: [NSLocalizedDescriptionKey : clientErrorCode.descriptionString()]))
    }
    
    /*
    //Actually PRIVATE! Do not call from outside. Has to be internally visible as NSTimer won't find it otherwise
    
    func sendWithRentransmissionHandling() {
        sendPendingMessage()
        
        if retransmissionCounter < kMaxRetransmit {
            var timeout = kAckTimeout * pow(2.0, Double(retransmissionCounter)) * (kAckRandomFactor - (Double(arc4random()) / Double(UINT32_MAX) % 0.5));
            currentTransmitWait += timeout
            transmissionTimer = NSTimer(timeInterval: timeout, target: self, selector: "sendWithRentransmissionHandling", userInfo: nil, repeats: false)
            retransmissionCounter++
        }
        else {
            transmissionTimer = NSTimer(timeInterval: kMaxTransmitWait - currentTransmitWait, target: self, selector: "notifyNoResponseExpected", userInfo: nil, repeats: false)
        }
        NSRunLoop.currentRunLoop().addTimer(transmissionTimer, forMode: NSRunLoopCommonModes)
    }
    
    //Actually PRIVATE! Do not call from outside. Has to be internally visible as NSTimer won't find it otherwise
    
    func notifyNoResponseExpected() {
        closeTransmission()
        notifyDelegateWithErrorCode(.NoResponseExpectedError)
    }
*/
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
        
        responseMessage.messageId = message.messageId
        responseMessage.token = message.token
        responseMessage.addressData = message.addressData
        
        return responseMessage
    }
}

extension SCServer: GCDAsyncUdpSocketDelegate {
    func udpSocket(sock: GCDAsyncUdpSocket!, didReceiveData data: NSData!, fromAddress address: NSData!, withFilterContext filterContext: AnyObject!) {
        if let message = SCMessage.fromData(data) {
            
            //Filter
            
            var resultType: SCType
            switch message.type {
            case .Reset:
                return
            case .Acknowledgement:
                if let tuple = pendingMessagesForEndpoints[address], oldTimer = tuple.1 where tuple.0.messageId == message.messageId {
                    oldTimer.invalidate()
                    pendingMessagesForEndpoints[address] = (tuple.0, nil)
                }
                return
            case .Confirmable:
                resultType = .Acknowledgement
            default:
                resultType = .NonConfirmable
            }
            message.addressData = address
            
            if message.code == SCCodeValue(classValue: 0, detailValue: 00) || message.code.classValue >= 1 {
                if message.type == .Confirmable || message.type == .NonConfirmable {
                    sendMessageWithType(.Reset, code: SCCodeValue(classValue: 0, detailValue: 00), payload: nil, messageId: message.messageId, addressData: address)
                }
                return
            }
            
            //URI-Path
            
            var resultResource: SCResourceModel!
            for resource in resources {
                if resource.name == message.completeUriPath() {
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

                //GET
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
