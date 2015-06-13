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
}

enum SCAllowedRoute: UInt {
    case Get = 0b1
    case Post = 0b10
    case Put = 0b100
    case Delete = 0b1000
}

protocol SCResourceModel {
    var name: String { get }
    var allowedRoutes: UInt { get }

    var maxAgeValue: UInt! { get set }
    var etag: NSData! { get set }

    
    func dataForGet(#queryDictionary: [String : String], options: [Int : [NSData]]) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!)?
    func dataForPost(#queryDictionary: [String : String], options: [Int : [NSData]], requestData: NSData?) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!, locationUri: String!)?
    func dataForPut(#queryDictionary: [String : String], options: [Int : [NSData]], requestData: NSData?) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!, locationUri: String!)?
    func dataForDelete(#queryDictionary: [String : String], options: [Int : [NSData]]) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!)?
}

class SCServer: NSObject {
   
    var delegate: SCServerDelegate?
    private var currentRequestMessages: [SCMessage]!
    private let port: UInt16
    private var udpSocket: GCDAsyncUdpSocket!
    private var udpSocketTag: Int = 0
    
    lazy var resources = [SCResourceModel]()

    init?(port: UInt16) {
        self.port = port
        super.init()
        
        if !setUpUdpSocket() {
            return nil
        }
    }
    
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
        sendMessage(emptyMessage, toAddress: addressData)
    }
    
    private func sendMessage(message: SCMessage, toAddress addressData: NSData) {
        udpSocket?.sendData(message.toData()!, toAddress: addressData, withTimeout: 0, tag: udpSocketTag)
        udpSocketTag = (udpSocketTag % Int.max) + 1
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
                return //TODO handle Separate Messagesjtus
            case .Confirmable:
                resultType = .Acknowledgement
            default:
                resultType = .NonConfirmable
            }
            
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
                var responseMessage: SCMessage!
                var resultTuple: (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!, locationUri: String!)!
                
                switch message.code {
                case SCCodeValue(classValue: 0, detailValue: 01) where resultResource.allowedRoutes & SCAllowedRoute.Get.rawValue == SCAllowedRoute.Get.rawValue:
                    if let (statusCode, payloadData, contentFormat) = resultResource.dataForGet(queryDictionary: message.uriQueryDictionary(), options: message.options) {
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
                    responseMessage = SCMessage(code: resultTuple.statusCode, type: resultType, payload: resultTuple.payloadData)
                    
                    if resultTuple.contentFormat != nil {
                        var contentFormatByteArray = resultTuple.contentFormat.rawValue.toByteArray()
                        responseMessage.addOption(SCOption.ContentFormat.rawValue, data: NSData(bytes: &contentFormatByteArray, length: contentFormatByteArray.count))
                    }
                    
                    if resultTuple.locationUri != nil {
                        if let (pathDataArray, queryDataArray) = SCMessage.getPathAndQueryDataArrayFromUriString(resultTuple.locationUri) where pathDataArray.count > 0 {
                            responseMessage.options[SCOption.LocationPath.rawValue] = pathDataArray
                            if queryDataArray.count > 0 {
                                responseMessage.options[SCOption.LocationQuery.rawValue] = queryDataArray
                            }
                        }
                    }
                    
                    if resultResource.maxAgeValue != nil {
                        var byteArray = resultResource.maxAgeValue.toByteArray()
                        responseMessage.addOption(SCOption.MaxAge.rawValue, data: NSData(bytes: &byteArray, length: byteArray.count))
                    }
                    
                    if resultResource.etag != nil {
                        responseMessage.addOption(SCOption.Etag.rawValue, data: resultResource.etag)
                    }
                    
                    responseMessage.messageId = message.messageId
                    responseMessage.token = message.token
                    sendMessage(responseMessage, toAddress: address)
                    delegate?.swiftCoapServer(self, didHandleRequestWithCode: message.code, forResource: resultResource)
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
    }
}
