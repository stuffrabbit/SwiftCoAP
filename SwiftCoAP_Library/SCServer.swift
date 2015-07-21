//
//  SCServer.swift
//  SwiftCoAP
//
//  Created by Wojtek Kordylewski on 03.06.15.
//  Copyright (c) 2015 Wojtek Kordylewski. All rights reserved.
//

import UIKit


//MARK:
//MARK: SC Server Delegate Protocol implementation

protocol SCServerDelegate {
    
    //Tells the delegate that an error occured during or before transmission (refer to the "SCServerErrorCode" Enum)
    func swiftCoapServer(server: SCServer, didFailWithError error: NSError)
    
    //Tells the delegate that a request on a particular resource was successfully handled and a response was or will be provided with the given response code
    func swiftCoapServer(server: SCServer, didHandleRequestWithCode requestCode: SCCodeValue, forResource resource: SCResourceModel, withResponseCode responseCode: SCCodeValue)
    
    //Tells the delegate that a recently received request with a uripath was rejected with a particular reponse (error) code (e.g. Method Not Allowed, Not Found, etc.)
    func swiftCoapServer(server: SCServer, didRejectRequestWithCode requestCode: SCCodeValue, forPath path: String, withResponseCode responseCode: SCCodeValue)
    
    //Tells the delegate that a separate response was processed
    func swiftCoapServer(server: SCServer, didSendSeparateResponseMessage: SCMessage, number: Int)
    
    //Tells the delegate that all registered observers for the particular resource will be notified due to a change of its data representation
    func swiftCoapServer(server: SCServer, willUpdatedObserversForResource resource: SCResourceModel)
}


//MARK:
//MARK: SC Allowed Route Enumeration

enum SCAllowedRoute: UInt {
    case Get = 0b1
    case Post = 0b10
    case Put = 0b100
    case Delete = 0b1000
}


//MARK:
//MARK: SC Server Error Code Enumeration

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


//MARK:
//MARK: SC Server IMPLEMENTATION

class SCServer: NSObject {
    
    //MARK: Properties
    
    
    //INTERNAL PROPERTIES (allowed to modify)
    
    var delegate: SCServerDelegate?
    var autoBlock2SZX: UInt? = 2 { didSet { if let newValue = autoBlock2SZX { autoBlock2SZX = min(6, newValue) } } } //If not nil, Block2 transfer will be used automatically when the payload size exceeds the value 2^(autoBlock2SZX + 4). Valid Values: 0-6.
    var autoWellKnownCore = true //If set to true, the server will automatically provide responses for the resource "well-known/core" with its current resources.
    lazy var resources = [SCResourceModel]()
    
    //PRIVATE PROPERTIES
    
    private var udpSocket: GCDAsyncUdpSocket!
    private var udpSocketTag: Int = 0
    
    private lazy var pendingMessagesForEndpoints = [NSData : [(SCMessage, NSTimer?)]]()
    private lazy var registeredObserverForResource = [SCResourceModel : [(UInt64, NSData, UInt, UInt?)]]() //Token, Address, SequenceNumber, PrefferedBlock2SZX
    private lazy var block1UploadsForEndpoints = [NSData : [(SCResourceModel, UInt, NSData?)]]()
    
    
    //MARK: Internal Methods (allowed to use)
    
    
    //Convenience initializer (failable): Starts server on initialization.
    
    convenience init?(port: UInt16) {
        self.init()
        
        if !start(port) {
            return nil //UDP Setup failed
        }
    }
    
    
    //Start server manually, with the given port
    
    func start(port: UInt16 = 5683) -> Bool {
        if udpSocket == nil {
            udpSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: dispatch_get_main_queue())
            
            do {
                try udpSocket!.bindToPort(port)
                try udpSocket!.beginReceiving()
            } catch {
                return false
            }
        }
        
        return true
    }
    
    
    //Close UDP socket and server ativity
    
    func close() {
        udpSocket?.close()
        udpSocket = nil
    }
    
    
    //Reset Context Information
    
    func reset() {
        pendingMessagesForEndpoints = [:]
        registeredObserverForResource = [:]
        block1UploadsForEndpoints = [:]
        resources = []
    }
    
    
    //Call this method when your resource is ready to process a separate response. The concerned resource must return true for the method `willHandleDataAsynchronouslyForGet(...)`. It is necessary to pass the original message and the resource (both received in `willHandleDataAsynchronouslyForGet`) so that the server is able to retrieve the current context. Additionay, you have to pass the typical "values" tuple which form the response (as described in SCMessage -> SCResourceModel)
    
    func didCompleteAsynchronousRequestForOriginalMessage(message: SCMessage, resource: SCResourceModel, values:(statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!)) {
        let type: SCType = message.type == .Confirmable ? .Confirmable : .NonConfirmable
        if let separateMessage = createMessageForValues((values.statusCode, values.payloadData, values.contentFormat, nil), withType: type, relatedMessage: message, requestedResource: resource) {
            separateMessage.messageId = UInt16(arc4random_uniform(0xFFFF) &+ 1)
            setupReliableTransmissionOfMessage(separateMessage, forResource: resource)
        }
    }
    
    
    //Call this method when the given resource has updated its data representation in order to notify all registered users (and has "observable" set to true)
    
    func updateRegisteredObserversForResource(resource: SCResourceModel) {
        if var valueArray = registeredObserverForResource[resource] {
            for var i = 0; i < valueArray.count; i++ {
                let (token, address, sequenceNumber, prefferredBlock2SZX) = valueArray[i]
                let notification = SCMessage(code: SCCodeValue(classValue: 2, detailValue: 05)!, type: .Confirmable, payload: resource.dataRepresentation)
                notification.token = token
                notification.messageId = UInt16(arc4random_uniform(0xFFFF) &+ 1)
                notification.addressData = address
                let newSequenceNumber = (sequenceNumber + 1) % UInt(pow(2.0, 24))
                var byteArray = newSequenceNumber.toByteArray()
                notification.addOption(SCOption.Observe.rawValue, data: NSData(bytes: &byteArray, length: byteArray.count))
                handleBlock2ServerRequirementsForMessage(notification, preferredBlockSZX: prefferredBlock2SZX)
                valueArray[i] = (token, address, newSequenceNumber, prefferredBlock2SZX)
                registeredObserverForResource[resource] = valueArray
                setupReliableTransmissionOfMessage(notification, forResource: resource)
            }
        }
        delegate?.swiftCoapServer(self, willUpdatedObserversForResource: resource)
    }
    
    
    // MARK: Private Methods
    
    private func setupReliableTransmissionOfMessage(message: SCMessage, forResource resource: SCResourceModel) {
        if let addressData = message.addressData {
            var timer: NSTimer!
            if message.type == .Confirmable {
                message.resourceForConfirmableResponse = resource
                let timeout = SCMessage.kAckTimeout * 2.0 * (SCMessage.kAckRandomFactor - (Double(arc4random()) / Double(UINT32_MAX) % 0.5));
                timer = NSTimer(timeInterval: timeout, target: self, selector: Selector("handleRetransmission:"), userInfo: ["retransmissionCount" : 1, "totalTime" : timeout, "message" : message, "resource" : resource], repeats: false)
                NSRunLoop.currentRunLoop().addTimer(timer, forMode: NSRunLoopCommonModes)
            }
            sendMessage(message)
            
            if var contextArray = pendingMessagesForEndpoints[addressData] {
                let newTuple: (SCMessage, NSTimer?) = (message, timer)
                contextArray += [newTuple]
                pendingMessagesForEndpoints[addressData] = contextArray
            }
            else {
                pendingMessagesForEndpoints[addressData] = [(message, timer)]
            }
        }
    }
    
    private func sendMessageWithType(type: SCType, code: SCCodeValue, payload: NSData?, messageId: UInt16, addressData: NSData, token: UInt64 = 0, options: [Int: [NSData]]! = nil) {
        let emptyMessage = SCMessage(code: code, type: type, payload: payload)
        emptyMessage.messageId = messageId
        emptyMessage.token = token
        emptyMessage.addressData = addressData
        if options != nil {
            emptyMessage.options = options
        }
        sendMessage(emptyMessage)
    }
    
    private func sendMessage(message: SCMessage) {
        udpSocket?.sendData(message.toData()!, toAddress: message.addressData, withTimeout: 0, tag: udpSocketTag)
        udpSocketTag = (udpSocketTag % Int.max) + 1
    }
    
    
    //Actually PRIVATE! Do not call from outside. Has to be internally visible as NSTimer won't find it otherwise
    
    func handleRetransmission(timer: NSTimer) {
        let retransmissionCount = timer.userInfo!["retransmissionCount"] as! Int
        let totalTime = timer.userInfo!["totalTime"] as! Double
        let message = timer.userInfo!["message"] as! SCMessage
        let resource = timer.userInfo!["resource"] as! SCResourceModel
        sendMessage(message)
        delegate?.swiftCoapServer(self, didSendSeparateResponseMessage: message, number: retransmissionCount)
        
        if let addressData = message.addressData, var contextArray = pendingMessagesForEndpoints[addressData] {
            let nextTimer: NSTimer
            if retransmissionCount < SCMessage.kMaxRetransmit {
                let timeout = SCMessage.kAckTimeout * pow(2.0, Double(retransmissionCount)) * (SCMessage.kAckRandomFactor - (Double(arc4random()) / Double(UINT32_MAX) % 0.5));
                nextTimer = NSTimer(timeInterval: timeout, target: self, selector: Selector("handleRetransmission:"), userInfo: ["retransmissionCount" : retransmissionCount + 1, "totalTime" : totalTime + timeout, "message" : message, "resource" : resource], repeats: false)
            }
            else {
                nextTimer = NSTimer(timeInterval: SCMessage.kMaxTransmitWait - totalTime, target: self, selector: Selector("notifyNoResponseExpected:"), userInfo: ["message" : message, "resource" : resource], repeats: false)
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
        let message = timer.userInfo!["message"] as! SCMessage
        let resource = timer.userInfo!["resource"] as! SCResourceModel
        
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
        delegate?.swiftCoapServer(self, didFailWithError: NSError(domain: SCMessage.kCoapErrorDomain, code: clientErrorCode.rawValue, userInfo: [NSLocalizedDescriptionKey : clientErrorCode.descriptionString()]))
    }
    
    private func handleBlock2ServerRequirementsForMessage(message: SCMessage, preferredBlockSZX: UInt?) {
        var req = autoBlock2SZX
        if let adjustedSZX = preferredBlockSZX {
            if let currentSZX = req {
                req = min(currentSZX, adjustedSZX)
            }
            else {
                req = adjustedSZX
            }
        }
        
        if let activeBlock2SZX = req, currentPayload = message.payload where currentPayload.length > Int(pow(2, Double(4 + activeBlock2SZX))) {
            let blockValue = UInt(activeBlock2SZX) + 8
            var byteArray = blockValue.toByteArray()
            message.addOption(SCOption.Block2.rawValue, data: NSData(bytes: &byteArray, length: byteArray.count))
            message.payload = currentPayload.subdataWithRange(NSMakeRange(0, Int(pow(2, Double(activeBlock2SZX + 4)))))
        }
    }
    
    private func createMessageForValues(values: (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!, locationUri: String!), withType type: SCType, relatedMessage message: SCMessage, requestedResource resource: SCResourceModel) -> SCMessage? {
        let responseMessage = SCMessage(code: values.statusCode, type: type, payload: values.payloadData)
        
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
        
        if message.code == SCCodeValue(classValue: 0, detailValue: 01) {
            if resource.maxAgeValue != nil {
                var byteArray = resource.maxAgeValue.toByteArray()
                responseMessage.addOption(SCOption.MaxAge.rawValue, data: NSData(bytes: &byteArray, length: byteArray.count))
            }
            
            if resource.etag != nil  {
                responseMessage.addOption(SCOption.Etag.rawValue, data: resource.etag)
            }
        }
        
        //Block 2
        if let block2ValueArray = message.options[SCOption.Block2.rawValue], block2Data = block2ValueArray.first {
            var actualValue = UInt.fromData(block2Data)
            var requestedBlockSZX = min(actualValue & 0b111, 6)
            actualValue >>= 4
            
            if let activeBlock2SZX = autoBlock2SZX where activeBlock2SZX < requestedBlockSZX {
                requestedBlockSZX = activeBlock2SZX
            }
            
            let fixedByteSize = pow(2, Double(requestedBlockSZX + 4))
            
            if let currentPayload = values.payloadData {
                let blocksCount = UInt(ceil(Double(currentPayload.length) / fixedByteSize))
                if actualValue >= blocksCount {
                    //invalid block requested
                    respondWithErrorCode(SCCodeSample.BadOption.codeValue(), diagnosticPayload: "Invalid Block Requested".dataUsingEncoding(NSUTF8StringEncoding), forMessage: message, withType: message.type == .Confirmable ? .Acknowledgement : .NonConfirmable)
                    return nil
                }
                else {
                    var nextBlockLength: Int
                    var blockValue = (UInt(actualValue) << 4) + UInt(requestedBlockSZX)
                    if actualValue < blocksCount - 1 {
                        blockValue += 8
                        nextBlockLength = Int(fixedByteSize)
                    }
                    else {
                        nextBlockLength = currentPayload.length - Int(fixedByteSize) * Int(actualValue)
                    }
                    var byteArray = blockValue.toByteArray()
                    responseMessage.addOption(SCOption.Block2.rawValue, data: NSData(bytes: &byteArray, length: byteArray.count))
                    responseMessage.payload = currentPayload.subdataWithRange(NSMakeRange(Int(fixedByteSize) * Int(actualValue), nextBlockLength))
                }
            }
        }
        else {
            handleBlock2ServerRequirementsForMessage(responseMessage, preferredBlockSZX: nil)
        }
        
        //Block 1
        if let block1ValueArray = message.options[SCOption.Block1.rawValue] {
            responseMessage.options[SCOption.Block1.rawValue] = block1ValueArray //Echo the option
        }
        
        //Observe
        if resource.observable, let observeValueArray = message.options[SCOption.Observe.rawValue], observeValue = observeValueArray.first, msgAddr = message.addressData {
            if observeValue.length > 0 && UInt.fromData(observeValue) == 1 {
                deregisterObserveForResource(resource, address: msgAddr)
            }
            else {
                //Register for Observe
                var newValueArray: [(UInt64, NSData, UInt, UInt?)]
                var currentSequenceNumber: UInt = 0
                var prefferredBlock2SZX: UInt?
                if let block2ValueArray = message.options[SCOption.Block2.rawValue], block2Data = block2ValueArray.first {
                    let blockValue = UInt.fromData(block2Data)
                    prefferredBlock2SZX = blockValue & 0b111
                }
                
                if var valueArray = registeredObserverForResource[resource] {
                    if let index = getIndexOfObserverInValueArray(valueArray, address: msgAddr) {
                        let (_, _, sequenceNumber, _) = valueArray[index]
                        let newSequenceNumber = (sequenceNumber + 1) % UInt(pow(2.0, 24))
                        currentSequenceNumber = UInt(newSequenceNumber)
                        valueArray[index] = (message.token, msgAddr, newSequenceNumber, prefferredBlock2SZX)
                    }
                    else {
                        valueArray += [(message.token, msgAddr, 0, prefferredBlock2SZX)]
                    }
                    newValueArray = valueArray
                }
                else {
                    newValueArray = [(message.token, msgAddr, 0, prefferredBlock2SZX)]
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
    
    private func getIndexOfObserverInValueArray(valueArray: [(UInt64, NSData, UInt, UInt?)], address: NSData) -> Int? {
        for var i = 0; i < valueArray.count; i++ {
            let (_, add, _, _) = valueArray[i]
            if add == address {
                return i
            }
        }
        return nil
    }
    
    private func retrievePayloadAfterBlock1HandlingWithMessage(message: SCMessage, resultResource: SCResourceModel) -> NSData? {
        var currentPayload = message.payload
        
        if let block1ValueArray = message.options[SCOption.Block1.rawValue], blockData = block1ValueArray.first, address = message.addressData {
            let blockAsInt = UInt.fromData(blockData)
            let blockNumber = blockAsInt >> 4
            if var uploadArray = block1UploadsForEndpoints[address] {
                for var i = 0; i < uploadArray.count; i++ {
                    let (resource, sequenceNumber, storedPayload) = uploadArray[i]
                    if resource == resultResource {
                        if sequenceNumber + 1 != blockNumber {
                            respondWithErrorCode(SCCodeSample.RequestEntityIncomplete.codeValue(), diagnosticPayload: "Incomplete Transmission".dataUsingEncoding(NSUTF8StringEncoding), forMessage: message, withType: message.type == .Confirmable ? .Acknowledgement : .NonConfirmable)
                            return nil
                        }
                        let newPayload = NSMutableData(data: storedPayload ?? NSData())
                        newPayload.appendData(message.payload ?? NSData())
                        currentPayload = newPayload
                        
                        if blockAsInt & 8 == 8 {
                            //more bit is set: Store Information
                            uploadArray[i] = (resource, sequenceNumber + 1, currentPayload)
                            block1UploadsForEndpoints[address] = uploadArray
                            sendMessageWithType(.Confirmable, code: SCCodeSample.Continue.codeValue(), payload: nil, messageId: message.messageId, addressData: address, token: message.token, options: [SCOption.Block1.rawValue : block1ValueArray])
                            return nil
                        }
                        else {
                            //No more blocks will be received, cleanup context
                            uploadArray.removeAtIndex(i)
                            if uploadArray.count > 0 {
                                block1UploadsForEndpoints[address] = uploadArray
                            }
                            else {
                                block1UploadsForEndpoints.removeValueForKey(address)
                            }
                        }
                        break
                    }
                }
            }
            else if blockNumber == 0 {
                if blockAsInt & 8 == 8 {
                    block1UploadsForEndpoints[address] = [(resultResource, 0, currentPayload)]
                    sendMessageWithType(.Confirmable, code: SCCodeSample.Continue.codeValue(), payload: nil, messageId: message.messageId, addressData: address, token: message.token, options: [SCOption.Block1.rawValue : block1ValueArray])
                    return nil
                }
            }
            else {
                respondWithErrorCode(SCCodeSample.RequestEntityIncomplete.codeValue(), diagnosticPayload: "Incomplete Transmission".dataUsingEncoding(NSUTF8StringEncoding), forMessage: message, withType: message.type == .Confirmable ? .Acknowledgement : .NonConfirmable)
                return nil
            }
        }
        return currentPayload
    }
    
    func respondWithErrorCode(responseCode: SCCodeValue, diagnosticPayload: NSData?, forMessage message: SCMessage, withType type: SCType) {
        if let address = message.addressData {
            sendMessageWithType(type, code: responseCode, payload: diagnosticPayload, messageId: message.messageId, addressData: address, token: message.token)
            delegate?.swiftCoapServer(self, didRejectRequestWithCode: message.code, forPath: message.completeUriPath(), withResponseCode: responseCode)
        }
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
                    sendMessageWithType(.Reset, code: SCCodeValue(classValue: 0, detailValue: 00)!, payload: nil, messageId: message.messageId, addressData: address)
                }
                return
            }
            
            //URI-Path
            
            var resultResource: SCResourceModel!
            let completeUri =  message.completeUriPath()
            if completeUri == ".well-known/core" && autoWellKnownCore {
                var wellKnownString = ""
                for resource in resources {
                    wellKnownString += "</\(resource.name)>"
                    if resource != resources.last && resources.count > 0 {
                        wellKnownString += ","
                    }
                }
                if let wellKnownData = wellKnownString.dataUsingEncoding(NSUTF8StringEncoding) {
                    let wellKnownResponseMessage = SCMessage(code: SCCodeValue(classValue: 2, detailValue: 05)!, type: resultType, payload: wellKnownData)
                    wellKnownResponseMessage.messageId = message.messageId
                    wellKnownResponseMessage.token = message.token
                    wellKnownResponseMessage.addressData = address
                    var hashInt = data.hashValue
                    wellKnownResponseMessage.addOption(SCOption.Etag.rawValue, data: NSData(bytes: &hashInt, length: sizeof(Int)))
                    var contentValue: UInt8 = UInt8(SCContentFormat.LinkFormat.rawValue)
                    wellKnownResponseMessage.addOption(SCOption.ContentFormat.rawValue, data: NSData(bytes: &contentValue, length: 1))
                    handleBlock2ServerRequirementsForMessage(wellKnownResponseMessage, preferredBlockSZX: nil)
                    sendMessage(wellKnownResponseMessage)
                    return
                }
            }
            else {
                for resource in resources {
                    if resource.name == completeUri {
                        resultResource = resource
                        break
                    }
                }
            }
            
            if resultResource != nil {
                var resultTuple: (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!, locationUri: String!)?
                
                switch message.code {
                case SCCodeValue(classValue: 0, detailValue: 01)! where resultResource.allowedRoutes & SCAllowedRoute.Get.rawValue == SCAllowedRoute.Get.rawValue:
                    //ETAG verification
                    if resultResource.etag != nil, let etagValueArray = message.options[SCOption.Etag.rawValue] {
                        for etagData in etagValueArray {
                            if etagData == resultResource.etag {
                                sendMessageWithType(resultType, code: SCCodeSample.Valid.codeValue(), payload: nil, messageId: message.messageId, addressData: address, token: message.token, options: [SCOption.Etag.rawValue : [etagData]])
                                delegate?.swiftCoapServer(self, didHandleRequestWithCode: message.code, forResource: resultResource, withResponseCode: SCCodeSample.Valid.codeValue())
                                return
                            }
                        }
                    }
                    
                    if resultResource.willHandleDataAsynchronouslyForGet(queryDictionary: message.uriQueryDictionary(), options: message.options, originalMessage: message) {
                        if message.type == .Confirmable {
                            sendMessageWithType(.Acknowledgement, code: SCCodeValue(classValue: 0, detailValue: 00)!, payload: nil, messageId: message.messageId, addressData: address)
                        }
                        delegate?.swiftCoapServer(self, didHandleRequestWithCode: message.code, forResource: resultResource, withResponseCode: SCCodeValue(classValue: 0, detailValue: 00)!)
                        return
                    }
                    else if let (statusCode, payloadData, contentFormat) = resultResource.dataForGet(queryDictionary: message.uriQueryDictionary(), options: message.options) {
                        resultTuple = (statusCode, payloadData, contentFormat, nil)
                    }
                case SCCodeValue(classValue: 0, detailValue: 02)! where resultResource.allowedRoutes & SCAllowedRoute.Post.rawValue == SCAllowedRoute.Post.rawValue:
                    if let payload = retrievePayloadAfterBlock1HandlingWithMessage(message, resultResource: resultResource) {
                        if let tuple = resultResource.dataForPost(queryDictionary: message.uriQueryDictionary(), options: message.options, requestData: payload) {
                            resultTuple = tuple
                        }
                    }
                    else {
                        return
                    }
                case SCCodeValue(classValue: 0, detailValue: 03)! where resultResource.allowedRoutes & SCAllowedRoute.Put.rawValue == SCAllowedRoute.Put.rawValue:
                    if let payload = retrievePayloadAfterBlock1HandlingWithMessage(message, resultResource: resultResource) {
                        if let tuple = resultResource.dataForPut(queryDictionary: message.uriQueryDictionary(), options: message.options, requestData: payload) {
                            resultTuple = tuple
                        }
                    }
                    else {
                        return
                    }
                case SCCodeValue(classValue: 0, detailValue: 04)! where resultResource.allowedRoutes & SCAllowedRoute.Delete.rawValue == SCAllowedRoute.Delete.rawValue:
                    if let (statusCode, payloadData, contentFormat) = resultResource.dataForDelete(queryDictionary: message.uriQueryDictionary(), options: message.options) {
                        resultTuple = (statusCode, payloadData, contentFormat, nil)
                    }
                default:
                    respondWithErrorCode(SCCodeSample.MethodNotAllowed.codeValue(), diagnosticPayload: "Method Not Allowed".dataUsingEncoding(NSUTF8StringEncoding), forMessage: message, withType: resultType)
                    return
                }
                
                if let finalTuple = resultTuple, responseMessage = createMessageForValues(finalTuple, withType: resultType, relatedMessage: message, requestedResource: resultResource) {
                    sendMessage(responseMessage)
                    delegate?.swiftCoapServer(self, didHandleRequestWithCode: message.code, forResource: resultResource, withResponseCode: responseMessage.code)
                }
                else {
                    respondWithErrorCode(SCCodeSample.MethodNotAllowed.codeValue(), diagnosticPayload: "Method Not Allowed".dataUsingEncoding(NSUTF8StringEncoding), forMessage: message, withType: resultType)
                }
            }
            else {
                respondWithErrorCode(SCCodeValue(classValue: 4, detailValue: 04)!, diagnosticPayload: "Not Found".dataUsingEncoding(NSUTF8StringEncoding), forMessage: message, withType: resultType)
            }
        }
    }
    
    func udpSocket(sock: GCDAsyncUdpSocket!, didNotSendDataWithTag tag: Int, dueToError error: NSError!) {
        notifyDelegateWithErrorCode(.UdpSocketSendError)
    }
}
