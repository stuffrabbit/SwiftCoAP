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

protocol SCServerDelegate: class {
    
    //Tells the delegate that an error occured during or before transmission (refer to the "SCServerErrorCode" Enum)
    func swiftCoapServer(_ server: SCServer, didFailWithError error: NSError)
    
    //Tells the delegate that a request on a particular resource was successfully handled and a response was or will be provided with the given response code
    func swiftCoapServer(_ server: SCServer, didHandleRequestWithCode requestCode: SCCodeValue, forResource resource: SCResourceModel, withResponseCode responseCode: SCCodeValue)
    
    //Tells the delegate that a recently received request with a uripath was rejected with a particular reponse (error) code (e.g. Method Not Allowed, Not Found, etc.)
    func swiftCoapServer(_ server: SCServer, didRejectRequestWithCode requestCode: SCCodeValue, forPath path: String, withResponseCode responseCode: SCCodeValue)
    
    //Tells the delegate that a separate response was processed
    func swiftCoapServer(_ server: SCServer, didSendSeparateResponseMessage: SCMessage, number: Int)
    
    //Tells the delegate that all registered observers for the particular resource will be notified due to a change of its data representation
    func swiftCoapServer(_ server: SCServer, willUpdatedObserversForResource resource: SCResourceModel)
}


//MARK:
//MARK: SC Server Error Code Enumeration

enum SCServerErrorCode: Int {
    case transportLayerError, receivedInvalidMessageError, noResponseExpectedError
    
    func descriptionString() -> String {
        switch self {
        case .transportLayerError:
            return "Failed to send data via the given Transport Layer"
        case .receivedInvalidMessageError:
            return "Data received was not a valid CoAP Message"
        case .noResponseExpectedError:
            return "The recipient does not respond"
        }
    }
}


//MARK:
//MARK: SC Server IMPLEMENTATION

class SCServer: NSObject {
    fileprivate class SCAddressWrapper: NSObject {
        let hostname: String
        let port: UInt16
        override var hash: Int {
            get { return hostname.hashValue &+ port.hashValue }
        }
        
        init(hostname: String, port: UInt16) {
            self.hostname = hostname
            self.port = port
        }
        
        override func isEqual(_ object: Any?) -> Bool {
            if let other = object as? SCAddressWrapper, other.hostname == self.hostname && other.port == self.port {
                return true
            }
            return false
        }
    }
    
    
    //MARK: Properties
    
    
    //INTERNAL PROPERTIES (allowed to modify)
    
    weak var delegate: SCServerDelegate?
    var autoBlock2SZX: UInt? = 2 { didSet { if let newValue = autoBlock2SZX { autoBlock2SZX = min(6, newValue) } } } //If not nil, Block2 transfer will be used automatically when the payload size exceeds the value 2^(autoBlock2SZX + 4). Valid Values: 0-6.
    var autoWellKnownCore = true //If set to true, the server will automatically provide responses for the resource "well-known/core" with its current resources.
    lazy var resources = [SCResourceModel]()
    
    //PRIVATE PROPERTIES
    fileprivate var transportLayerObject: SCCoAPTransportLayerProtocol!
    fileprivate lazy var pendingMessagesForEndpoints = [SCAddressWrapper : [(SCMessage, Timer?)]]()
    fileprivate lazy var registeredObserverForResource = [SCResourceModel : [(UInt64, String, UInt16, UInt, UInt?)]]() //Token, hostname, port, SequenceNumber, PrefferedBlock2SZX
    fileprivate lazy var block1UploadsForEndpoints = [SCAddressWrapper : [(SCResourceModel, UInt, Data?)]]()
    
    
    //MARK: Internal Methods (allowed to use)
    
    
    //Initializer (failable): Starts server on initialization.
    
    init?(delegate: SCServerDelegate?, transportLayerObject: SCCoAPTransportLayerProtocol = SCCoAPUDPTransportLayer(port: 5683)) {
        self.delegate = delegate
        super.init()
        self.transportLayerObject = transportLayerObject
        do {
            try start()
            self.transportLayerObject.transportLayerDelegate = self
        }
        catch {
            return nil
        }
    }
    
    //Start server manually, with the given port
    
    func start() throws {
        try self.transportLayerObject?.startListening()
    }
    
    
    //Close UDP socket and server ativity
    
    func close() {
        self.transportLayerObject?.closeTransmission()
    }
    
    
    //Reset Context Information
    
    func reset() {
        pendingMessagesForEndpoints = [:]
        registeredObserverForResource = [:]
        block1UploadsForEndpoints = [:]
        resources = []
    }
    
    
    //Call this method when your resource is ready to process a separate response. The concerned resource must return true for the method `willHandleDataAsynchronouslyForGet(...)`. It is necessary to pass the original message and the resource (both received in `willHandleDataAsynchronouslyForGet`) so that the server is able to retrieve the current context. Additionay, you have to pass the typical "values" tuple which form the response (as described in SCMessage -> SCResourceModel)
    
    func didCompleteAsynchronousRequestForOriginalMessage(_ message: SCMessage, resource: SCResourceModel, values: (statusCode: SCCodeValue, payloadData: Data?, contentFormat: SCContentFormat?, locationUri: String?)) {
        let type: SCType = message.type == .confirmable ? .confirmable : .nonConfirmable
        if let separateMessage = createMessageForValues((values.statusCode, values.payloadData, values.contentFormat, values.locationUri), withType: type, relatedMessage: message, requestedResource: resource) {
            separateMessage.messageId = UInt16(arc4random_uniform(0xFFFF) &+ 1)
            setupReliableTransmissionOfMessage(separateMessage, forResource: resource)
        }
    }
    
    
    //Call this method when the given resource has updated its data representation in order to notify all registered users (and has "observable" set to true)
    
    func updateRegisteredObserversForResource(_ resource: SCResourceModel) {
        if var valueArray = registeredObserverForResource[resource] {
            for i in 0 ..< valueArray.count {
                let (token, hostname, port, sequenceNumber, prefferredBlock2SZX) = valueArray[i]
                let notification = SCMessage(code: SCCodeValue(classValue: 2, detailValue: 05)!, type: .confirmable, payload: resource.dataRepresentation)
                notification.token = token
                notification.messageId = UInt16(arc4random_uniform(0xFFFF) &+ 1)
                notification.hostName = hostname
                notification.port = port
                let newSequenceNumber = (sequenceNumber + 1) % UInt(pow(2.0, 24))
                var byteArray = newSequenceNumber.toByteArray()
                notification.addOption(SCOption.observe.rawValue, data: Data(bytes: &byteArray, count: byteArray.count))
                handleBlock2ServerRequirementsForMessage(notification, preferredBlockSZX: prefferredBlock2SZX)
                valueArray[i] = (token, hostname, port, newSequenceNumber, prefferredBlock2SZX)
                registeredObserverForResource[resource] = valueArray
                setupReliableTransmissionOfMessage(notification, forResource: resource)
            }
        }
        delegate?.swiftCoapServer(self, willUpdatedObserversForResource: resource)
    }
    
    
    // MARK: Private Methods
    
    fileprivate func setupReliableTransmissionOfMessage(_ message: SCMessage, forResource resource: SCResourceModel) {
        if let host = message.hostName, let port = message.port {
            var timer: Timer!
            if message.type == .confirmable {
                message.resourceForConfirmableResponse = resource
                let timeout = SCMessage.kAckTimeout * 2.0 * (SCMessage.kAckRandomFactor - ((Double(arc4random()) / Double(UINT32_MAX)).truncatingRemainder(dividingBy: 0.5)));
                timer = Timer(timeInterval: timeout, target: self, selector: #selector(SCServer.handleRetransmission(_:)), userInfo: ["retransmissionCount" : 1, "totalTime" : timeout, "message" : message, "resource" : resource], repeats: false)
                RunLoop.current.add(timer, forMode: RunLoop.Mode.common)
            }
            sendMessage(message)
            let addressWrapper = SCAddressWrapper(hostname: host, port: port)
            if var contextArray = pendingMessagesForEndpoints[addressWrapper] {
                let newTuple: (SCMessage, Timer?) = (message, timer)
                contextArray += [newTuple]
                pendingMessagesForEndpoints[addressWrapper] = contextArray
            }
            else {
                pendingMessagesForEndpoints[addressWrapper] = [(message, timer)]
            }
        }
    }
    
    fileprivate func sendMessageWithType(_ type: SCType, code: SCCodeValue, payload: Data?, messageId: UInt16, hostname: String, port: UInt16, token: UInt64 = 0, options: [Int: [Data]]! = nil) {
        let emptyMessage = SCMessage(code: code, type: type, payload: payload)
        emptyMessage.messageId = messageId
        emptyMessage.token = token
        emptyMessage.hostName = hostname
        emptyMessage.port = port
        if let opt = options {
            emptyMessage.options = opt
        }
        sendMessage(emptyMessage)
    }
    
    fileprivate func sendMessage(_ message: SCMessage) {
        if let messageData = message.toData(), let host = message.hostName, let port = message.port {
            do {
                try transportLayerObject.sendCoAPData(messageData, toHost: host, port: port)
            }
            catch SCCoAPTransportLayerError.sendError(let errorDescription) {
                notifyDelegateWithTransportLayerErrorDescription(errorDescription)
            }
            catch SCCoAPTransportLayerError.setupError(let errorDescription) {
                notifyDelegateWithTransportLayerErrorDescription(errorDescription)
            }
            catch {}
        }
    }
    
    
    //Actually PRIVATE! Do not call from outside. Has to be internally visible as NSTimer won't find it otherwise
    
    @objc func handleRetransmission(_ timer: Timer) {
        guard let userInfoDict = timer.userInfo as? [String: Any] else { return }
        
        let retransmissionCount = userInfoDict["retransmissionCount"] as! Int
        let totalTime = userInfoDict["totalTime"] as! Double
        let message = userInfoDict["message"] as! SCMessage
        let resource = userInfoDict["resource"] as! SCResourceModel
        sendMessage(message)
        delegate?.swiftCoapServer(self, didSendSeparateResponseMessage: message, number: retransmissionCount)
        
        if let hostname = message.hostName, let port = message.port {
            let wrapper = SCAddressWrapper(hostname: hostname, port: port)
            if  var contextArray = pendingMessagesForEndpoints[wrapper] {
                let nextTimer: Timer
                if retransmissionCount < SCMessage.kMaxRetransmit {
                    let timeout = SCMessage.kAckTimeout * pow(2.0, Double(retransmissionCount)) * (SCMessage.kAckRandomFactor - ((Double(arc4random()) / Double(UINT32_MAX)).truncatingRemainder(dividingBy: 0.5)));
                    nextTimer = Timer(timeInterval: timeout, target: self, selector: #selector(SCServer.handleRetransmission(_:)), userInfo: ["retransmissionCount" : retransmissionCount + 1, "totalTime" : totalTime + timeout, "message" : message, "resource" : resource], repeats: false)
                }
                else {
                    nextTimer = Timer(timeInterval: SCMessage.kMaxTransmitWait - totalTime, target: self, selector: #selector(SCServer.notifyNoResponseExpected(_:)), userInfo: ["message" : message, "resource" : resource], repeats: false)
                }
                RunLoop.current.add(nextTimer, forMode: RunLoop.Mode.common)
                
                //Update context
                for i in 0 ..< contextArray.count {
                    let tuple = contextArray[i]
                    if tuple.0 == message {
                        contextArray[i] = (tuple.0, nextTimer)
                        pendingMessagesForEndpoints[wrapper] = contextArray
                        break
                    }
                }
            }
        }
    }
    
    
    //Actually PRIVATE! Do not call from outside. Has to be internally visible as NSTimer won't find it otherwise
    
    @objc func notifyNoResponseExpected(_ timer: Timer)  {
        guard let userInfoDict = timer.userInfo as? [String: Any] else { return }

        let message = userInfoDict["message"] as! SCMessage
        let resource = userInfoDict["resource"] as! SCResourceModel
        
        removeContextForMessage(message)
        notifyDelegateWithErrorCode(.noResponseExpectedError)
        
        if message.options[SCOption.observe.rawValue] != nil, let hostname = message.hostName, let port = message.port {
            deregisterObserveForResource(resource, hostname: hostname, port: port)
        }
    }
    
    fileprivate func notifyDelegateWithTransportLayerErrorDescription(_ errorDescription: String) {
        delegate?.swiftCoapServer(self, didFailWithError: NSError(domain: SCMessage.kCoapErrorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey : errorDescription]))
    }
    
    fileprivate func removeContextForMessage(_ message: SCMessage) {
        if let hostname = message.hostName, let port = message.port {
            let wrapper = SCAddressWrapper(hostname: hostname, port: port)
            if var contextArray = pendingMessagesForEndpoints[wrapper] {
                func removeFromContextAtIndex(_ index: Int) {
                    contextArray.remove(at: index)
                    if contextArray.count > 0 {
                        pendingMessagesForEndpoints[wrapper] = contextArray
                    }
                    else {
                        pendingMessagesForEndpoints.removeValue(forKey: wrapper)
                    }
                }
                
                for i in 0 ..< contextArray.count {
                    let tuple = contextArray[i]
                    if tuple.0.messageId == message.messageId {
                        if let oldTimer = tuple.1 {
                            oldTimer.invalidate()
                        }
                        if message.type == .reset && tuple.0.options[SCOption.observe.rawValue] != nil, let resource = tuple.0.resourceForConfirmableResponse  {
                            deregisterObserveForResource(resource, hostname: hostname, port: port)
                        }
                        removeFromContextAtIndex(i)
                        break
                    }
                }
            }
        }
    }
    
    fileprivate func notifyDelegateWithErrorCode(_ clientErrorCode: SCServerErrorCode) {
        delegate?.swiftCoapServer(self, didFailWithError: NSError(domain: SCMessage.kCoapErrorDomain, code: clientErrorCode.rawValue, userInfo: [NSLocalizedDescriptionKey : clientErrorCode.descriptionString()]))
    }
    
    fileprivate func handleBlock2ServerRequirementsForMessage(_ message: SCMessage, preferredBlockSZX: UInt?) {
        var req = autoBlock2SZX
        if let adjustedSZX = preferredBlockSZX {
            if let currentSZX = req {
                req = min(currentSZX, adjustedSZX)
            }
            else {
                req = adjustedSZX
            }
        }
        
        if let activeBlock2SZX = req, let currentPayload = message.payload, currentPayload.count > Int(pow(2, Double(4 + activeBlock2SZX))) {
            let blockValue = UInt(activeBlock2SZX) + 8
            var byteArray = blockValue.toByteArray()
            message.addOption(SCOption.block2.rawValue, data: Data(bytes: &byteArray, count: byteArray.count))
            message.payload = currentPayload.subdata(in: (0 ..< Int(pow(2, Double(activeBlock2SZX + 4)))))
        }
    }
    
    fileprivate func createMessageForValues(_ values: (statusCode: SCCodeValue, payloadData: Data?, contentFormat: SCContentFormat?, locationUri: String?), withType type: SCType, relatedMessage message: SCMessage, requestedResource resource: SCResourceModel) -> SCMessage? {
        let responseMessage = SCMessage(code: values.statusCode, type: type, payload: values.payloadData)
        
        if values.contentFormat != nil, var contentFormatByteArray = values.contentFormat?.rawValue.toByteArray() {
            responseMessage.addOption(SCOption.contentFormat.rawValue, data: Data(bytes: &contentFormatByteArray, count: contentFormatByteArray.count))
        }
        
        if let locationUri = values.locationUri {
            if let (pathDataArray, queryDataArray) = SCMessage.getPathAndQueryDataArrayFromUriString(locationUri), pathDataArray.count > 0 {
                responseMessage.options[SCOption.locationPath.rawValue] = pathDataArray
                if queryDataArray.count > 0 {
                    responseMessage.options[SCOption.locationQuery.rawValue] = queryDataArray
                }
            }
        }
        
        if message.code == SCCodeValue(classValue: 0, detailValue: 01) {
            if let maxAgeVal = resource.maxAgeValue {
                var byteArray = maxAgeVal.toByteArray()
                responseMessage.addOption(SCOption.maxAge.rawValue, data: Data(bytes: &byteArray, count: byteArray.count))
            }
            
            if let etag = resource.etag {
                responseMessage.addOption(SCOption.etag.rawValue, data: etag)
            }
        }
        
        //Block 2
        if let block2ValueArray = message.options[SCOption.block2.rawValue], let block2Data = block2ValueArray.first {
            var actualValue = UInt.fromData(block2Data)
            var requestedBlockSZX = min(actualValue & 0b111, 6)
            actualValue >>= 4
            
            if let activeBlock2SZX = autoBlock2SZX, activeBlock2SZX < requestedBlockSZX {
                requestedBlockSZX = activeBlock2SZX
            }
            
            let fixedByteSize = pow(2, Double(requestedBlockSZX + 4))
            
            if let currentPayload = values.payloadData {
                let blocksCount = UInt(ceil(Double(currentPayload.count) / fixedByteSize))
                if actualValue >= blocksCount {
                    //invalid block requested
                    respondWithErrorCode(SCCodeSample.badOption.codeValue(), diagnosticPayload: "Invalid Block Requested".data(using: String.Encoding.utf8), forMessage: message, withType: message.type == .confirmable ? .acknowledgement : .nonConfirmable)
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
                        nextBlockLength = currentPayload.count - Int(fixedByteSize) * Int(actualValue)
                    }
                    var byteArray = blockValue.toByteArray()
                    responseMessage.addOption(SCOption.block2.rawValue, data: Data(bytes: &byteArray, count: byteArray.count))
                    let startPos = Int(fixedByteSize) * Int(actualValue)
                    responseMessage.payload = currentPayload.subdata(in: (startPos ..< startPos + nextBlockLength))
                }
            }
        }
        else {
            handleBlock2ServerRequirementsForMessage(responseMessage, preferredBlockSZX: nil)
        }
        
        //Block 1
        if let block1ValueArray = message.options[SCOption.block1.rawValue] {
            responseMessage.options[SCOption.block1.rawValue] = block1ValueArray //Echo the option
        }
        
        //Observe
        if resource.observable, let observeValueArray = message.options[SCOption.observe.rawValue], let observeValue = observeValueArray.first, let hostname = message.hostName, let port = message.port {
            if observeValue.count > 0 && UInt.fromData(observeValue) == 1 {
                deregisterObserveForResource(resource, hostname: hostname, port: port)
            }
            else {
                //Register for Observe
                var newValueArray: [(UInt64, String, UInt16, UInt, UInt?)]
                var currentSequenceNumber: UInt = 0
                var prefferredBlock2SZX: UInt?
                if let block2ValueArray = message.options[SCOption.block2.rawValue], let block2Data = block2ValueArray.first {
                    let blockValue = UInt.fromData(block2Data)
                    prefferredBlock2SZX = blockValue & 0b111
                }
                
                if var valueArray = registeredObserverForResource[resource] {
                    if let index = getIndexOfObserverInValueArray(valueArray, hostname: hostname, port: port) {
                        let (_, _, _, sequenceNumber, _) = valueArray[index]
                        let newSequenceNumber = (sequenceNumber + 1) % UInt(pow(2.0, 24))
                        currentSequenceNumber = UInt(newSequenceNumber)
                        valueArray[index] = (message.token, hostname, port, newSequenceNumber, prefferredBlock2SZX)
                    }
                    else {
                        valueArray.append((message.token, hostname, port, 0, prefferredBlock2SZX))
                    }
                    newValueArray = valueArray
                }
                else {
                    newValueArray = [(message.token, hostname, port, 0, prefferredBlock2SZX)]
                }
                
                registeredObserverForResource[resource] = newValueArray
                var byteArray = currentSequenceNumber.toByteArray()
                responseMessage.addOption(SCOption.observe.rawValue, data: Data(bytes: &byteArray, count: byteArray.count))
            }
        }
        
        
        responseMessage.messageId = message.messageId
        responseMessage.token = message.token
        responseMessage.hostName = message.hostName
        responseMessage.port = message.port
        
        return responseMessage
    }
    
    fileprivate func deregisterObserveForResource(_ resource: SCResourceModel, hostname: String, port: UInt16 ) {
        if var valueArray = registeredObserverForResource[resource], let index = getIndexOfObserverInValueArray(valueArray, hostname: hostname, port: port) {
            valueArray.remove(at: index)
            if valueArray.count == 0 {
                registeredObserverForResource.removeValue(forKey: resource)
            }
            else {
                registeredObserverForResource[resource] = valueArray
            }
        }
    }
    
    fileprivate func getIndexOfObserverInValueArray(_ valueArray: [(UInt64, String, UInt16, UInt, UInt?)], hostname: String, port: UInt16) -> Int? {
        for i in 0 ..< valueArray.count {
            let (_, currentHost, currentPort, _, _) = valueArray[i]
            if currentHost == hostname && currentPort == port {
                return i
            }
        }
        return nil
    }
    
    fileprivate func retrievePayloadAfterBlock1HandlingWithMessage(_ message: SCMessage, resultResource: SCResourceModel) -> Data? {
        var currentPayload = message.payload
        
        if let block1ValueArray = message.options[SCOption.block1.rawValue], let blockData = block1ValueArray.first, let hostname = message.hostName, let port = message.port {
            let blockAsInt = UInt.fromData(blockData)
            let blockNumber = blockAsInt >> 4
            let wrapper = SCAddressWrapper(hostname: hostname, port: port)
            if var uploadArray = block1UploadsForEndpoints[wrapper] {
                for i in 0 ..< uploadArray.count {
                    let (resource, sequenceNumber, storedPayload) = uploadArray[i]
                    if resource == resultResource {
                        if sequenceNumber + 1 != blockNumber {
                            respondWithErrorCode(SCCodeSample.requestEntityIncomplete.codeValue(), diagnosticPayload: "Incomplete Transmission".data(using: String.Encoding.utf8), forMessage: message, withType: message.type == .confirmable ? .acknowledgement : .nonConfirmable)
                            return nil
                        }
                        var newPayload = NSData(data: storedPayload ?? Data()) as Data
                        newPayload.append(message.payload ?? Data())
                        currentPayload = newPayload
                        
                        if blockAsInt & 8 == 8 {
                            //more bit is set: Store Information
                            uploadArray[i] = (resource, sequenceNumber + 1, currentPayload as Data?)
                            block1UploadsForEndpoints[wrapper] = uploadArray
                            sendMessageWithType(.confirmable, code: SCCodeSample.continue.codeValue(), payload: nil, messageId: message.messageId, hostname: hostname, port: port, token: message.token, options: [SCOption.block1.rawValue : block1ValueArray])
                            return nil
                        }
                        else {
                            //No more blocks will be received, cleanup context
                            uploadArray.remove(at: i)
                            if uploadArray.count > 0 {
                                block1UploadsForEndpoints[wrapper] = uploadArray
                            }
                            else {
                                block1UploadsForEndpoints.removeValue(forKey: wrapper)
                            }
                        }
                        break
                    }
                }
            }
            else if blockNumber == 0 {
                if blockAsInt & 8 == 8 {
                    block1UploadsForEndpoints[SCAddressWrapper(hostname: hostname, port: port)] = [(resultResource, 0, currentPayload as Optional<Data>)]
                    sendMessageWithType(.confirmable, code: SCCodeSample.continue.codeValue(), payload: nil, messageId: message.messageId, hostname: hostname, port: port, token: message.token, options: [SCOption.block1.rawValue : block1ValueArray])
                    return nil
                }
            }
            else {
                respondWithErrorCode(SCCodeSample.requestEntityIncomplete.codeValue(), diagnosticPayload: "Incomplete Transmission".data(using: String.Encoding.utf8), forMessage: message, withType: message.type == .confirmable ? .acknowledgement : .nonConfirmable)
                return nil
            }
        }
        return currentPayload as Data?
    }
    
    func respondWithErrorCode(_ responseCode: SCCodeValue, diagnosticPayload: Data?, forMessage message: SCMessage, withType type: SCType) {
        if let hostname = message.hostName, let port = message.port {
            sendMessageWithType(type, code: responseCode, payload: diagnosticPayload, messageId: message.messageId, hostname: hostname, port: port, token: message.token)
            delegate?.swiftCoapServer(self, didRejectRequestWithCode: message.code, forPath: message.completeUriPath(), withResponseCode: responseCode)
        }
    }
}


// MARK:
// MARK: SC Server Extension
// MARK: SC CoAP Transport Layer Delegate

extension SCServer: SCCoAPTransportLayerDelegate {
    func transportLayerObject(_ transportLayerObject: SCCoAPTransportLayerProtocol, didReceiveData data: Data, fromHost host: String, port: UInt16) {
        if let message = SCMessage.fromData(data) {
            message.hostName = host
            message.port = port
            
            //Filter
            
            var resultType: SCType
            switch message.type {
            case .confirmable:
                resultType = .acknowledgement
            case .nonConfirmable:
                resultType = .nonConfirmable
            default:
                removeContextForMessage(message)
                return
            }
            
            if message.code == SCCodeValue(classValue: 0, detailValue: 00) || message.code.classValue >= 1 {
                if message.type == .confirmable || message.type == .nonConfirmable {
                    sendMessageWithType(.reset, code: SCCodeValue(classValue: 0, detailValue: 00)!, payload: nil, messageId: message.messageId, hostname: host, port: port)
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
                if let wellKnownData = wellKnownString.data(using: String.Encoding.utf8) {
                    let wellKnownResponseMessage = SCMessage(code: SCCodeValue(classValue: 2, detailValue: 05)!, type: resultType, payload: wellKnownData)
                    wellKnownResponseMessage.messageId = message.messageId
                    wellKnownResponseMessage.token = message.token
                    wellKnownResponseMessage.hostName = host
                    wellKnownResponseMessage.port = port
                    var hashInt = data.hashValue
                    wellKnownResponseMessage.addOption(SCOption.etag.rawValue, data: Data(bytes: &hashInt, count: MemoryLayout<Int>.size))
                    var contentValue: UInt8 = UInt8(SCContentFormat.linkFormat.rawValue)
                    wellKnownResponseMessage.addOption(SCOption.contentFormat.rawValue, data: Data(bytes: &contentValue, count: 1))
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
                
                func didHandleAsyncRequestForRoute(_ route: SCAllowedRoute) -> Bool {
                    if resultResource.willHandleDataAsynchronouslyForRoute(route, queryDictionary: message.uriQueryDictionary(), options: message.options, originalMessage: message) {
                        if message.type == .confirmable {
                            sendMessageWithType(.acknowledgement, code: SCCodeValue(classValue: 0, detailValue: 00)!, payload: nil, messageId: message.messageId, hostname: host, port: port)
                        }
                        delegate?.swiftCoapServer(self, didHandleRequestWithCode: message.code, forResource: resultResource, withResponseCode: SCCodeValue(classValue: 0, detailValue: 00)!)
                        return true
                    }
                    return false
                }
                
                var resultTuple: (statusCode: SCCodeValue, payloadData: Data?, contentFormat: SCContentFormat?, locationUri: String?)?
                
                switch message.code {
                case SCCodeValue(classValue: 0, detailValue: 01)! where resultResource.allowedRoutes & SCAllowedRoute.get.rawValue == SCAllowedRoute.get.rawValue:
                    //ETAG verification
                    if resultResource.etag != nil, let etagValueArray = message.options[SCOption.etag.rawValue] {
                        for etagData in etagValueArray {
                            if etagData == resultResource.etag {
                                sendMessageWithType(resultType, code: SCCodeSample.valid.codeValue(), payload: nil, messageId: message.messageId, hostname: host, port: port, token: message.token, options: [SCOption.etag.rawValue : [etagData]])
                                delegate?.swiftCoapServer(self, didHandleRequestWithCode: message.code, forResource: resultResource, withResponseCode: SCCodeSample.valid.codeValue())
                                return
                            }
                        }
                    }
                    
                    if didHandleAsyncRequestForRoute(.get) {
                        return
                    }
                    else if let (statusCode, payloadData, contentFormat) = resultResource.dataForGet(queryDictionary: message.uriQueryDictionary(), options: message.options) {
                        resultTuple = (statusCode, payloadData, contentFormat, nil)
                    }
                case SCCodeValue(classValue: 0, detailValue: 02)! where resultResource.allowedRoutes & SCAllowedRoute.post.rawValue == SCAllowedRoute.post.rawValue:
                    if let payload = retrievePayloadAfterBlock1HandlingWithMessage(message, resultResource: resultResource) {
                        if didHandleAsyncRequestForRoute(.post) {
                            return
                        }
                        else if let tuple = resultResource.dataForPost(queryDictionary: message.uriQueryDictionary(), options: message.options, requestData: payload) {
                            resultTuple = tuple
                        }
                    }
                    else {
                        return
                    }
                case SCCodeValue(classValue: 0, detailValue: 03)! where resultResource.allowedRoutes & SCAllowedRoute.put.rawValue == SCAllowedRoute.put.rawValue:
                    if let payload = retrievePayloadAfterBlock1HandlingWithMessage(message, resultResource: resultResource) {
                        if didHandleAsyncRequestForRoute(.put) {
                            return
                        }
                        else if let tuple = resultResource.dataForPut(queryDictionary: message.uriQueryDictionary(), options: message.options, requestData: payload) {
                            resultTuple = tuple
                        }
                    }
                    else {
                        return
                    }
                case SCCodeValue(classValue: 0, detailValue: 04)! where resultResource.allowedRoutes & SCAllowedRoute.delete.rawValue == SCAllowedRoute.delete.rawValue:
                    if didHandleAsyncRequestForRoute(.delete) {
                        return
                    }
                    else if let (statusCode, payloadData, contentFormat) = resultResource.dataForDelete(queryDictionary: message.uriQueryDictionary(), options: message.options) {
                        resultTuple = (statusCode, payloadData, contentFormat, nil)
                    }
                default:
                    respondWithErrorCode(SCCodeSample.methodNotAllowed.codeValue(), diagnosticPayload: "Method Not Allowed".data(using: String.Encoding.utf8), forMessage: message, withType: resultType)
                    return
                }
                
                if let finalTuple = resultTuple, let responseMessage = createMessageForValues(finalTuple, withType: resultType, relatedMessage: message, requestedResource: resultResource) {
                    sendMessage(responseMessage)
                    delegate?.swiftCoapServer(self, didHandleRequestWithCode: message.code, forResource: resultResource, withResponseCode: responseMessage.code)
                }
                else {
                    respondWithErrorCode(SCCodeSample.methodNotAllowed.codeValue(), diagnosticPayload: "Method Not Allowed".data(using: String.Encoding.utf8), forMessage: message, withType: resultType)
                }
            }
            else {
                respondWithErrorCode(SCCodeValue(classValue: 4, detailValue: 04)!, diagnosticPayload: "Not Found".data(using: String.Encoding.utf8), forMessage: message, withType: resultType)
            }
        }
    }
    
    func transportLayerObject(_ transportLayerObject: SCCoAPTransportLayerProtocol, didFailWithError error: NSError) {
        notifyDelegateWithErrorCode(.transportLayerError)
    }
}
