//
//  SCMessage.swift
//  SwiftCoAP
//
//  Created by Wojtek Kordylewski on 22.04.15.
//  Copyright (c) 2015 Wojtek Kordylewski. All rights reserved.
//

import UIKit


//MARK:
//MARK: SC Coap Transport Layer Error Enumeration

enum SCCoAPTransportLayerError: ErrorType {
    case SetupError(errorDescription: String), SendError(errorDescription: String)
}


//MARK:
//MARK: SC CoAP Transport Layer Delegate Protocol declaration. It is implemented by SCClient to receive responses. Your custom transport layer handler must call these callbacks to notify the SCClient object.

protocol SCCoAPTransportLayerDelegate: class {
    //CoAP Data Received
    func transportLayerObject(transportLayerObject: SCCoAPTransportLayerProtocol, didReceiveData data: NSData, fromHost host: String, port: UInt16)
    
    //Error occured. Provide an appropriate NSError object.
    func transportLayerObject(transportLayerObject: SCCoAPTransportLayerProtocol, didFailWithError error: NSError)
}


//MARK:
//MARK: SC CoAP Transport Layer Protocol declaration

protocol SCCoAPTransportLayerProtocol: class {
    //SCClient uses this property to assign itself as delegate
    weak var transportLayerDelegate: SCCoAPTransportLayerDelegate! { get set }
    
    //SClient calls this method when it wants to send CoAP data
    func sendCoAPData(data: NSData, toHost host: String, port: UInt16) throws
    
    //Called when the transmission is over. Clear your states (e.g. close sockets)
    func closeTransmission()
    
    //Start to listen for Messages. Prepare e.g. sockets for receiving data. This method will only be called by SCServer
    func startListening() throws
}



//MARK:
//MARK: SC CoAP UDP Transport Layer: This class is the default transport layer handler, sending data via UDP with help of GCDAsyncUdpSocket. If you want to create a custom transport layer handler, you have to create a custom class and adopt the SCCoAPTransportLayerProtocol. Next you have to pass your class to the init method of SCClient: init(delegate: SCClientDelegate?, transportLayerObject: SCCoAPTransportLayerProtocol). You will than get callbacks to send CoAP data and have to inform your delegate (in this case an object of type SCClient) when you receive a response by using the callbacks from SCCoAPTransportLayerDelegate.

final class SCCoAPUDPTransportLayer: NSObject {
    weak var transportLayerDelegate: SCCoAPTransportLayerDelegate!
    var udpSocket: GCDAsyncUdpSocket!
    var port: UInt16 = 0
    private var udpSocketTag: Int = 0
    
    convenience init(port: UInt16) {
        self.init()
        self.port = port
    }
    
    private func setUpUdpSocket() -> Bool {
        udpSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: dispatch_get_main_queue())
        do {
            try udpSocket!.bindToPort(port)
            try udpSocket!.beginReceiving()
        } catch {
            return false
        }
        return true
    }
}

extension SCCoAPUDPTransportLayer: SCCoAPTransportLayerProtocol {
    func sendCoAPData(data: NSData, toHost host: String, port: UInt16) throws {
        try startListening()
        udpSocket.sendData(data, toHost: host, port: port, withTimeout: 0, tag: udpSocketTag)
        udpSocketTag = (udpSocketTag % Int.max) + 1
    }
    
    func closeTransmission() {
        udpSocket.close()
        udpSocket = nil
    }
    
    func startListening() throws {
        if udpSocket == nil && !setUpUdpSocket() {
            udpSocket.close()
            udpSocket = nil
            throw SCCoAPTransportLayerError.SetupError(errorDescription: "Failed to setup UDP socket")
        }
    }
}

extension SCCoAPUDPTransportLayer: GCDAsyncUdpSocketDelegate {
    func udpSocket(sock: GCDAsyncUdpSocket!, didReceiveData data: NSData!, fromAddress address: NSData!, withFilterContext filterContext: AnyObject!) {
        transportLayerDelegate.transportLayerObject(self, didReceiveData: data, fromHost: GCDAsyncUdpSocket.hostFromAddress(address), port: GCDAsyncUdpSocket.portFromAddress(address))
    }
    
    func udpSocket(sock: GCDAsyncUdpSocket!, didNotSendDataWithTag tag: Int, dueToError error: NSError!) {
        transportLayerDelegate.transportLayerObject(self, didFailWithError: error)
    }
}


//MARK:
//MARK: SC Type Enumeration: Represents the CoAP types

enum SCType: Int {
    case Confirmable, NonConfirmable, Acknowledgement, Reset
    
    func shortString() -> String {
        switch self {
        case .Confirmable:
            return "CON"
        case .NonConfirmable:
            return "NON"
        case .Acknowledgement:
            return "ACK"
        case .Reset:
            return "RST"
        }
    }
    
    func longString() -> String {
        switch self {
        case .Confirmable:
            return "Confirmable"
        case .NonConfirmable:
            return "Non Confirmable"
        case .Acknowledgement:
            return "Acknowledgement"
        case .Reset:
            return "Reset"
        }
    }
    
    static func fromShortString(string: String) -> SCType? {
        switch string.uppercaseString {
        case "CON":
            return .Confirmable
        case "NON":
            return .NonConfirmable
        case "ACK":
            return .Acknowledgement
        case "RST":
            return .Reset
        default:
            return nil
        }
    }
}


//MARK:
//MARK: SC Option Enumeration: Represents the CoAP options

enum SCOption: Int {
    case IfMatch = 1
    case UriHost = 3
    case Etag = 4
    case IfNoneMatch = 5
    case Observe = 6
    case UriPort = 7
    case LocationPath = 8
    case UriPath = 11
    case ContentFormat = 12
    case MaxAge = 14
    case UriQuery = 15
    case Accept = 17
    case LocationQuery = 20
    case Block2 = 23
    case Block1 = 27
    case Size2 = 28
    case ProxyUri = 35
    case ProxyScheme = 39
    case Size1 = 60
    
    static let allValues = [IfMatch, UriHost, Etag, IfNoneMatch, Observe, UriPort, LocationPath, UriPath, ContentFormat, MaxAge, UriQuery, Accept, LocationQuery, Block2, Block1, Size2, ProxyUri, ProxyScheme, Size1]
    
    enum Format: Int {
        case Empty, Opaque, UInt, String
    }
    
    func toString() -> String {
        switch self {
        case .IfMatch:
            return "If_Match"
        case .UriHost:
            return "URI_Host"
        case .Etag:
            return "ETAG"
        case .IfNoneMatch:
            return "If_None_Match"
        case .Observe:
            return "Observe"
        case .UriPort:
            return "URI_Port"
        case .LocationPath:
            return "Location_Path"
        case .UriPath:
            return "URI_Path"
        case .ContentFormat:
            return "Content_Format"
        case .MaxAge:
            return "Max_Age"
        case .UriQuery:
            return "URI_Query"
        case .Accept:
            return "Accept"
        case .LocationQuery:
            return "Location_Query"
        case .Block2:
            return "Block2"
        case .Block1:
            return "Block1"
        case .Size2:
            return "Size2"
        case .ProxyUri:
            return "Proxy_URI"
        case .ProxyScheme:
            return "Proxy_Scheme"
        case .Size1:
            return "Size1"
        }
    }
    
    static func isNumberCritical(optionNo: Int) -> Bool {
        return optionNo % 2 == 1
    }
    
    func isCritical() -> Bool {
        return SCOption.isNumberCritical(self.rawValue)
    }
    
    static func isNumberUnsafe(optionNo: Int) -> Bool {
        return optionNo & 0b10 == 0b10
    }
    
    func isUnsafe() -> Bool {
        return SCOption.isNumberUnsafe(self.rawValue)
    }
    
    static func isNumberNoCacheKey(optionNo: Int) -> Bool {
        return optionNo & 0b11110 == 0b11100
    }
    
    func isNoCacheKey() -> Bool {
        return SCOption.isNumberNoCacheKey(self.rawValue)
    }
    
    static func isNumberRepeatable(optionNo: Int) -> Bool {
        switch optionNo {
        case SCOption.IfMatch.rawValue, SCOption.Etag.rawValue, SCOption.LocationPath.rawValue, SCOption.UriPath.rawValue, SCOption.UriQuery.rawValue, SCOption.LocationQuery.rawValue:
            return true
        default:
            return false
        }
    }
    
    func isRepeatable() -> Bool {
        return SCOption.isNumberRepeatable(self.rawValue)
    }
    
    func format() -> Format {
        switch self {
        case .IfNoneMatch:
            return .Empty
        case .IfMatch, .Etag:
            return .Opaque
        case .UriHost, .LocationPath, .UriPath, .UriQuery, .LocationQuery, .ProxyUri, .ProxyScheme:
            return .String
        default:
            return .UInt
        }
    }
    
    func dataForValueString(valueString: String) -> NSData? {
        return SCOption.dataForOptionValueString(valueString, format: format())
    }
    
    static func dataForOptionValueString(valueString: String, format: Format) -> NSData? {
        switch format {
        case .Empty:
            return nil
        case .Opaque:
            return NSData.fromOpaqueString(valueString)
        case .String:
            return valueString.dataUsingEncoding(NSUTF8StringEncoding)
        case .UInt:
            if let number = UInt(valueString) {
                var byteArray = number.toByteArray()
                return NSData(bytes: &byteArray, length: byteArray.count)
            }
            return nil
        }
    }
    
    func displayStringForData(data: NSData?) -> String {
        return SCOption.displayStringForFormat(format(), data: data)
    }
    
    static func displayStringForFormat(format: Format, data: NSData?) -> String {
        switch format {
        case .Empty:
            return "< Empty >"
        case .Opaque:
            if let valueData = data {
                return String.toHexFromData(valueData)
            }
            return "0x0"
        case .UInt:
            if let valueData = data {
                return String(UInt.fromData(valueData))
            }
            return "0"
        case .String:
            if let valueData = data, string = NSString(data: valueData, encoding: NSUTF8StringEncoding) as? String {
                return string
            }
            return "<<Format Error>>"
        }
    }
}


//MARK:
//MARK: SC Code Sample Enumeration: Provides the most common CoAP codes as raw values

enum SCCodeSample: Int {
    case Empty = 0
    case Get = 1
    case Post = 2
    case Put = 3
    case Delete = 4
    case Created = 65
    case Deleted = 66
    case Valid = 67
    case Changed = 68
    case Content = 69
    case Continue = 95
    case BadRequest = 128
    case Unauthorized = 129
    case BadOption = 130
    case Forbidden = 131
    case NotFound = 132
    case MethodNotAllowed = 133
    case NotAcceptable = 134
    case RequestEntityIncomplete = 136
    case PreconditionFailed = 140
    case RequestEntityTooLarge = 141
    case UnsupportedContentFormat = 143
    case InternalServerError = 160
    case NotImplemented = 161
    case BadGateway = 162
    case ServiceUnavailable = 163
    case GatewayTimeout = 164
    case ProxyingNotSupported = 165
    
    func codeValue() -> SCCodeValue! {
        return SCCodeValue.fromCodeSample(self)
    }
    
    func toString() -> String {
        switch self {
        case .Empty:
            return "Empty"
        case .Get:
            return "Get"
        case .Post:
            return "Post"
        case .Put:
            return "Put"
        case .Delete:
            return "Delete"
        case .Created:
            return "Created"
        case .Deleted:
            return "Deleted"
        case .Valid:
            return "Valid"
        case .Changed:
            return "Changed"
        case .Content:
            return "Content"
        case .Continue:
            return "Continue"
        case .BadRequest:
            return "Bad Request"
        case .Unauthorized:
            return "Unauthorized"
        case .BadOption:
            return "Bad Option"
        case .Forbidden:
            return "Forbidden"
        case .NotFound:
            return "Not Found"
        case .MethodNotAllowed:
            return "Method Not Allowed"
        case .NotAcceptable:
            return "Not Acceptable"
        case .RequestEntityIncomplete:
            return "Request Entity Incomplete"
        case .PreconditionFailed:
            return "Precondition Failed"
        case .RequestEntityTooLarge:
            return "Request Entity Too Large"
        case .UnsupportedContentFormat:
            return "Unsupported Content Format"
        case .InternalServerError:
            return "Internal Server Error"
        case .NotImplemented:
            return "Not Implemented"
        case .BadGateway:
            return "Bad Gateway"
        case .ServiceUnavailable:
            return "Service Unavailable"
        case .GatewayTimeout:
            return "Gateway Timeout"
        case .ProxyingNotSupported:
            return "Proxying Not Supported"
        }
    }
    
    static func stringFromCodeValue(codeValue: SCCodeValue) -> String? {
        return codeValue.toCodeSample()?.toString()
    }
}


//MARK:
//MARK: SC Content Format Enumeration

enum SCContentFormat: UInt {
    case Plain = 0
    case LinkFormat = 40
    case XML = 41
    case OctetStream = 42
    case EXI = 47
    case JSON = 50
    case CBOR = 60
    
    func needsStringUTF8Conversion() -> Bool {
        switch self {
        case .OctetStream, .EXI, .CBOR:
            return false
        default:
            return true
        }
    }
    
    func toString() -> String {
        switch self {
        case .Plain:
            return "Plain"
        case .LinkFormat:
            return "Link Format"
        case .XML:
            return "XML"
        case .OctetStream:
            return "Octet Stream"
        case .EXI:
            return "EXI"
        case .JSON:
            return "JSON"
        case .CBOR:
            return "CBOR"
        }
    }
}


//MARK:
//MARK: SC Code Value struct: Represents the CoAP code. You can easily apply the CoAP code syntax c.dd (e.g. SCCodeValue(classValue: 0, detailValue: 01) equals 0.01)

struct SCCodeValue: Equatable {
    let classValue: UInt8
    let detailValue: UInt8
    
    init(rawValue: UInt8) {
        let firstBits: UInt8 = rawValue >> 5
        let lastBits: UInt8 = rawValue & 0b00011111
        self.classValue = firstBits
        self.detailValue = lastBits
    }
    
    //classValue must not be larger than 7; detailValue must not be larger than 31
    init?(classValue: UInt8, detailValue: UInt8) {
        if classValue > 0b111 || detailValue > 0b11111 { return nil }
        
        self.classValue = classValue
        self.detailValue = detailValue
    }
    
    func toRawValue() -> UInt8 {
        return classValue << 5 + detailValue
    }
    
    func toCodeSample() -> SCCodeSample? {
        return SCCodeSample(rawValue: Int(toRawValue()))
    }
    
    static func fromCodeSample(code: SCCodeSample) -> SCCodeValue {
        return SCCodeValue(rawValue: UInt8(code.rawValue))
    }
    
    func toString() -> String {
        return String(format: "%i.%02d", classValue, detailValue)
    }
    
    func requestString() -> String? {
        switch self {
        case SCCodeValue(classValue: 0, detailValue: 01)!:
            return "GET"
        case SCCodeValue(classValue: 0, detailValue: 02)!:
            return "POST"
        case SCCodeValue(classValue: 0, detailValue: 03)!:
            return "PUT"
        case SCCodeValue(classValue: 0, detailValue: 04)!:
            return "DELETE"
        default:
            return nil
        }
    }
}

func ==(lhs: SCCodeValue, rhs: SCCodeValue) -> Bool {
    return lhs.classValue == rhs.classValue && lhs.detailValue == rhs.detailValue
}


//MARK:
//MARK: UInt Extension

public extension UInt {
    func toByteArray() -> [UInt8] {
        let byteLength = UInt(ceil(log2(Double(self + 1)) / 8))
        var byteArray = [UInt8]()
        for var i: UInt = 0; i < byteLength; i++ {
            byteArray.append(UInt8(((self) >> ((byteLength - i - 1) * 8)) & 0xFF))
        }
        return byteArray
    }
    
    static func fromData(data: NSData) -> UInt {
        var valueBytes = [UInt8](count: data.length, repeatedValue: 0)
        data.getBytes(&valueBytes, length: data.length)
        
        var actualValue: UInt = 0
        for var i = 0; i < valueBytes.count; i++ {
            actualValue += UInt(valueBytes[i]) << ((UInt(valueBytes.count) - UInt(i + 1)) * 8)
        }
        return actualValue
    }
}

//MARK:
//MARK: String Extension

extension String {
    static func toHexFromData(data: NSData) -> String {
        let string = data.description.stringByReplacingOccurrencesOfString(" ", withString: "")
        return "0x" + string.substringWithRange(Range<String.Index>(start: string.startIndex.advancedBy(1), end: string.endIndex.advancedBy(-1)))
    }
}

//MARK:
//MARK: NSData Extension

extension NSData {
    static func fromOpaqueString(string: String) -> NSData? {
        let comps = string.componentsSeparatedByString("x")
        if let lastString = comps.last, number = UInt(lastString, radix:16) where comps.count <= 2 {
            var byteArray = number.toByteArray()
            return NSData(bytes: &byteArray, length: byteArray.count)
        }
        return nil
    }
}

//MARK:
//MARK: Resource Implementation, used for SCServer

class SCResourceModel: NSObject {
    let name: String // Name of the resource
    let allowedRoutes: UInt // Bitmask of allowed routes (see SCAllowedRoutes enum)
    var maxAgeValue: UInt! // If not nil, every response will contain the provided MaxAge value
    private(set) var etag: NSData! // If not nil, every response to a GET request will contain the provided eTag. The etag is generated automatically whenever you update the dataRepresentation of the resource
    var dataRepresentation: NSData! {
        didSet {
            if var hashInt = dataRepresentation?.hashValue {
                etag = NSData(bytes: &hashInt, length: sizeof(Int))
            }
            else {
                etag = nil
            }
        }
    }// The current data representation of the resource. Needs to stay up to date
    var observable = false // If true, a response will contain the Observe option, and endpoints will be able to register as observers in SCServer. Call updateRegisteredObserversForResource(self), anytime your dataRepresentation changes.
    
    //Desigated initializer
    init(name: String, allowedRoutes: UInt) {
        self.name = name
        self.allowedRoutes = allowedRoutes
    }
    
    
    //The Methods for Data reception for allowed routes. SCServer will call the appropriate message upon the reception of a reqeuest. Override the respective methods, which match your allowedRoutes.
    //SCServer passes a queryDictionary containing the URI query content (e.g ["user_id": "23"]) and all options contained in the respective request. The POST and PUT methods provide the message's payload as well.
    //Refer to the example resources in the SwiftCoAPServerExample project for implementation examples.
    
    
    //This method lets you decide whether the current GET request shall be processed asynchronously, i.e. if true will be returned, an empty ACK will be sent, and you can provide the actual response by calling the servers "didCompleteAsynchronousRequestForOriginalMessage(...)". Note: "dataForGet" will not be called additionally if you return true.
    func willHandleDataAsynchronouslyForGet(queryDictionary queryDictionary: [String : String], options: [Int : [NSData]], originalMessage: SCMessage) -> Bool { return false }
    
    //The following methods require data for the given routes GET, POST, PUT, DELETE and must be overriden if needed. If you return nil, the server will respond with a "Method not allowed" error code (Make sure that you have set the allowed routes in the "allowedRoutes" bitmask property).
    //You have to return a tuple with a statuscode, optional payload, optional content format for your provided payload and (in case of POST and PUT) an optional locationURI.
    func dataForGet(queryDictionary queryDictionary: [String : String], options: [Int : [NSData]]) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!)? { return nil }
    func dataForPost(queryDictionary queryDictionary: [String : String], options: [Int : [NSData]], requestData: NSData?) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!, locationUri: String!)? { return nil }
    func dataForPut(queryDictionary queryDictionary: [String : String], options: [Int : [NSData]], requestData: NSData?) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!, locationUri: String!)? { return nil }
    func dataForDelete(queryDictionary queryDictionary: [String : String], options: [Int : [NSData]]) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!)? { return nil }
}

//MARK:
//MARK: SC Message IMPLEMENTATION

class SCMessage: NSObject {
    
    //MARK: Constants and Properties
    
    //CONSTANTS
    static let kCoapVersion = 0b01
    static let kProxyCoAPTypeKey = "COAP_TYPE"
    
    static let kCoapErrorDomain = "SwiftCoapErrorDomain"
    static let kAckTimeout = 2.0
    static let kAckRandomFactor = 1.5
    static let kMaxRetransmit = 4
    static let kMaxTransmitWait = 93.0
    
    let kDefaultMaxAgeValue: UInt = 60
    let kOptionOneByteExtraValue: UInt8 = 13
    let kOptionTwoBytesExtraValue: UInt8 = 14
    
    //INTERNAL PROPERTIES (allowed to modify)
    
    var code: SCCodeValue = SCCodeValue(classValue: 0, detailValue: 0)! //Code value is Empty by default
    var type: SCType = .Confirmable //Type is CON by default
    var payload: NSData? //Add a payload (optional)
    lazy var options = [Int: [NSData]]() //CoAP-Options. It is recommend to use the addOption(..) method to add a new option.
    
    //The following properties are modified by SCClient/SCServer. Modification has no effect and is therefore not recommended
    var blockBody: NSData? //Helper for Block1 tranmission. Used by SCClient, modification has no effect
    var hostName: String?
    var port: UInt16?
    var resourceForConfirmableResponse: SCResourceModel?
    var messageId: UInt16!
    var token: UInt64 = 0
    
    var timeStamp: NSDate?
    
    
    //MARK: Internal Methods (allowed to use)
    
    convenience init(code: SCCodeValue, type: SCType, payload: NSData?) {
        self.init()
        self.code = code
        self.type = type
        self.payload = payload
    }
    
    func equalForCachingWithMessage(message: SCMessage) -> Bool {
        if code == message.code && hostName == message.hostName && port == message.port {
            let firstSet = Set(options.keys)
            let secondSet = Set(message.options.keys)
            
            let exOr = firstSet.exclusiveOr(secondSet)
            
            for optNo in exOr {
                if !(SCOption.isNumberNoCacheKey(optNo)) { return false }
            }
            
            let interSect = firstSet.intersect(secondSet)
            
            for optNo in interSect {
                if !(SCOption.isNumberNoCacheKey(optNo)) && !(SCMessage.compareOptionValueArrays(options[optNo]!, second: message.options[optNo]!)) { return false }
            }
            return true
        }
        return false
    }
    
    static func compareOptionValueArrays(first: [NSData], second: [NSData]) -> Bool {
        if first.count != second.count { return false }
        
        for var i = 0; i < first.count; i++ {
            if !first[i].isEqualToData(second[i]) { return false }
        }
        
        return true
    }
    
    static func copyFromMessage(message: SCMessage) -> SCMessage {
        let copiedMessage = SCMessage(code: message.code, type: message.type, payload: message.payload)
        copiedMessage.options = message.options
        copiedMessage.hostName = message.hostName
        copiedMessage.port = message.port
        copiedMessage.messageId = message.messageId
        copiedMessage.token = message.token
        copiedMessage.timeStamp = message.timeStamp
        return copiedMessage
    }
    
    func isFresh() -> Bool {
        func validateMaxAge(value: UInt) -> Bool {
            if timeStamp != nil {
                let expirationDate = timeStamp!.dateByAddingTimeInterval(Double(value))
                return NSDate().compare(expirationDate) != .OrderedDescending
            }
            return false
        }
        
        if let maxAgeValues = options[SCOption.MaxAge.rawValue], firstData = maxAgeValues.first {
            return validateMaxAge(UInt.fromData(firstData))
        }
        
        return validateMaxAge(kDefaultMaxAgeValue)
    }
    
    func addOption(option: Int, data: NSData) {
        if var currentOptionValue = options[option] {
            currentOptionValue.append(data)
            options[option] = currentOptionValue
        }
        else {
            options[option] = [data]
        }
    }
    
    func toData() -> NSData? {
        var resultData: NSMutableData
        
        let tokenLength = Int(ceil(log2(Double(token + 1)) / 8))
        if tokenLength > 8 {
            return nil
        }
        let codeRawValue = code.toRawValue()
        let firstByte: UInt8 = UInt8((SCMessage.kCoapVersion << 6) | (type.rawValue << 4) | tokenLength)
        let actualMessageId: UInt16 = messageId ?? 0
        var byteArray: [UInt8] = [firstByte, codeRawValue, UInt8(actualMessageId >> 8), UInt8(actualMessageId & 0xFF)]
        resultData = NSMutableData(bytes: &byteArray, length: byteArray.count)
        
        if tokenLength > 0 {
            var tokenByteArray = [UInt8]()
            for var i = 0; i < tokenLength; i++ {
                tokenByteArray.append(UInt8(((token) >> UInt64((tokenLength - i - 1) * 8)) & 0xFF))
            }
            resultData.appendBytes(&tokenByteArray, length: tokenLength)
        }
        
        let sortedOptions = options.sort {
            $0.0 < $1.0
        }
        
        var previousDelta = 0
        for (key, valueArray) in sortedOptions {
            for value in valueArray {
                let optionDelta = key - previousDelta
                previousDelta += optionDelta
                
                var optionFirstByte: UInt8
                var extendedDelta: NSData?
                var extendedLength: NSData?
                
                if optionDelta >= Int(kOptionTwoBytesExtraValue) + 0xFF {
                    optionFirstByte = kOptionTwoBytesExtraValue << 4
                    let extendedDeltaValue: UInt16 = UInt16(optionDelta) - (UInt16(kOptionTwoBytesExtraValue) + 0xFF)
                    var extendedByteArray: [UInt8] = [UInt8(extendedDeltaValue >> 8), UInt8(extendedDeltaValue & 0xFF)]
                    
                    extendedDelta = NSData(bytes: &extendedByteArray, length: extendedByteArray.count)
                }
                else if optionDelta >= Int(kOptionOneByteExtraValue) {
                    optionFirstByte = kOptionOneByteExtraValue << 4
                    var extendedDeltaValue: UInt8 = UInt8(optionDelta) - kOptionOneByteExtraValue
                    extendedDelta = NSData(bytes: &extendedDeltaValue, length: 1)
                }
                else {
                    optionFirstByte = UInt8(optionDelta) << 4
                }
                
                if value.length >= Int(kOptionTwoBytesExtraValue) + 0xFF {
                    optionFirstByte += kOptionTwoBytesExtraValue
                    let extendedLengthValue: UInt16 = UInt16(value.length) - (UInt16(kOptionTwoBytesExtraValue) + 0xFF)
                    var extendedByteArray: [UInt8] = [UInt8(extendedLengthValue >> 8), UInt8(extendedLengthValue & 0xFF)]
                    
                    extendedLength = NSData(bytes: &extendedByteArray, length: extendedByteArray.count)
                }
                else if value.length >= Int(kOptionOneByteExtraValue) {
                    optionFirstByte += kOptionOneByteExtraValue
                    var extendedLengthValue: UInt8 = UInt8(value.length) - kOptionOneByteExtraValue
                    extendedLength = NSData(bytes: &extendedLengthValue, length: 1)
                }
                else {
                    optionFirstByte += UInt8(value.length)
                }
                
                resultData.appendBytes(&optionFirstByte, length: 1)
                if extendedDelta != nil {
                    resultData.appendData(extendedDelta!)
                }
                if extendedLength != nil {
                    resultData.appendData(extendedLength!)
                }
                
                resultData.appendData(value)
            }
        }
        
        if payload != nil {
            var payloadMarker: UInt8 = 0xFF
            resultData.appendBytes(&payloadMarker, length: 1)
            resultData.appendData(payload!)
        }
        //print("resultData for Sending: \(resultData)")
        return resultData
    }
    
    static func fromData(data: NSData) -> SCMessage? {
        if data.length < 4 { return nil }
        //print("parsing Message FROM Data: \(data)")
        //Unparse Header
        var parserIndex = 4
        var headerBytes = [UInt8](count: parserIndex, repeatedValue: 0)
        data.getBytes(&headerBytes, length: parserIndex)
        
        var firstByte = headerBytes[0]
        let tokenLenght = Int(firstByte) & 0xF
        firstByte >>= 4
        let type = SCType(rawValue: Int(firstByte) & 0b11)
        firstByte >>= 2
        if tokenLenght > 8 || type == nil || firstByte != UInt8(kCoapVersion)  { return nil }
        
        //Assign header values to CoAP Message
        let message = SCMessage()
        message.type = type!
        message.code = SCCodeValue(rawValue: headerBytes[1])
        message.messageId = (UInt16(headerBytes[2]) << 8) + UInt16(headerBytes[3])
        
        if tokenLenght > 0 {
            var tokenByteArray = [UInt8](count: tokenLenght, repeatedValue: 0)
            data.getBytes(&tokenByteArray, range: NSMakeRange(4, tokenLenght))
            for var i = 0; i < tokenByteArray.count; i++ {
                message.token += UInt64(tokenByteArray[i]) << ((UInt64(tokenByteArray.count) - UInt64(i + 1)) * 8)
            }
        }
        parserIndex += tokenLenght
        
        var currentOptDelta = 0
        while parserIndex < data.length {
            var nextByte: UInt8 = 0
            data.getBytes(&nextByte, range: NSMakeRange(parserIndex, 1))
            parserIndex++
            
            if nextByte == 0xFF {
                message.payload = data.subdataWithRange(NSMakeRange(parserIndex, data.length - parserIndex))
                break
            }
            else {
                let optLength = nextByte & 0xF
                nextByte >>= 4
                if nextByte == 0xF || optLength == 0xF { return nil }
                
                var finalDelta = 0
                switch nextByte {
                case 13:
                    data.getBytes(&finalDelta, range: NSMakeRange(parserIndex, 1))
                    finalDelta += 13
                    parserIndex++
                case 14:
                    var twoByteArray = [UInt8](count: 2, repeatedValue: 0)
                    data.getBytes(&twoByteArray, range: NSMakeRange(parserIndex, 2))
                    finalDelta = (Int(twoByteArray[0]) << 8) + Int(twoByteArray[1])
                    finalDelta += (14 + 0xFF)
                    parserIndex += 2
                default:
                    finalDelta = Int(nextByte)
                }
                finalDelta += currentOptDelta
                currentOptDelta = finalDelta
                var finalLenght = 0
                switch optLength {
                case 13:
                    data.getBytes(&finalLenght, range: NSMakeRange(parserIndex, 1))
                    finalLenght += 13
                    parserIndex++
                case 14:
                    var twoByteArray = [UInt8](count: 2, repeatedValue: 0)
                    data.getBytes(&twoByteArray, range: NSMakeRange(parserIndex, 2))
                    finalLenght = (Int(twoByteArray[0]) << 8) + Int(twoByteArray[1])
                    finalLenght += (14 + 0xFF)
                    parserIndex += 2
                default:
                    finalLenght = Int(optLength)
                }
                
                var optValue = NSData()
                if finalLenght > 0 {
                    optValue = data.subdataWithRange(NSMakeRange(parserIndex, finalLenght))
                    parserIndex += finalLenght
                }
                message.addOption(finalDelta, data: optValue)
            }
        }
        
        return message
    }
    
    func toHttpUrlRequestWithUrl() -> NSMutableURLRequest {
        let urlRequest = NSMutableURLRequest()
        if code != SCCodeSample.Get.codeValue() {
            urlRequest.HTTPMethod = code.requestString()!
        }
        
        for (key, valueArray) in options {
            for value in valueArray {
                if let option = SCOption(rawValue: key) {
                    urlRequest.addValue(option.displayStringForData(value), forHTTPHeaderField: option.toString().uppercaseString)
                }
            }
        }
        urlRequest.HTTPBody = payload
        
        return urlRequest
    }
    
    static func fromHttpUrlResponse(urlResponse: NSHTTPURLResponse, data: NSData!) -> SCMessage {
        let message = SCMessage()
        message.payload = data
        message.code = SCCodeValue(rawValue: UInt8(urlResponse.statusCode & 0xff))
        if let typeString = urlResponse.allHeaderFields[SCMessage.kProxyCoAPTypeKey] as? String, type = SCType.fromShortString(typeString) {
            message.type = type
        }
        else {
            message.type = .Acknowledgement
        }
        
        for opt in SCOption.allValues {
            if let optValue = urlResponse.allHeaderFields["HTTP_\(opt.toString().uppercaseString)"] as? String {
                let optValueData = opt.dataForValueString(optValue) ?? NSData()
                message.options[opt.rawValue] = [optValueData]
            }
        }
        return message
    }
    
    func completeUriPath() -> String {
        var finalPathString: String = ""
        if let pathDataArray = options[SCOption.UriPath.rawValue] {
            for var i = 0; i < pathDataArray.count; i++ {
                if let pathString = NSString(data: pathDataArray[i], encoding: NSUTF8StringEncoding) {
                    if  i > 0 { finalPathString += "/"}
                    finalPathString += String(pathString)
                }
            }
        }
        return finalPathString
    }
    
    func uriQueryDictionary() -> [String : String] {
        var resultDict = [String : String]()
        if let queryDataArray = options[SCOption.UriQuery.rawValue] {
            for queryData in queryDataArray {
                if let queryString = NSString(data: queryData, encoding: NSUTF8StringEncoding) {
                    let splitArray = queryString.componentsSeparatedByString("=")
                    if splitArray.count == 2 {
                        resultDict[splitArray.first!] = splitArray.last!
                    }
                }
            }
        }
        return resultDict
    }
    
    static func getPathAndQueryDataArrayFromUriString(uriString: String) -> (pathDataArray: [NSData], queryDataArray: [NSData])? {
        
        func dataArrayFromString(string: String!, withSeparator separator: String) -> [NSData] {
            var resultDataArray = [NSData]()
            if string != nil {
                let stringArray = string.componentsSeparatedByString(separator)
                for subString in stringArray {
                    if let data = subString.dataUsingEncoding(NSUTF8StringEncoding) {
                        resultDataArray.append(data)
                    }
                }
            }
            return resultDataArray
        }
        
        let splitArray = uriString.componentsSeparatedByString("?")
        
        if splitArray.count <= 2 {
            let resultPathDataArray = dataArrayFromString(splitArray.first, withSeparator: "/")
            let resultQueryDataArray = splitArray.count == 2 ? dataArrayFromString(splitArray.last, withSeparator: "&") : []
            
            return (resultPathDataArray, resultQueryDataArray)
        }
        return nil
    }
    
    func inferredContentFormat() -> SCContentFormat {
        guard let contentFormatArray = options[SCOption.ContentFormat.rawValue], contentFormatData = contentFormatArray.first, contentFormat = SCContentFormat(rawValue: UInt.fromData(contentFormatData)) else { return .Plain }
        return contentFormat
    }
    
    func payloadRepresentationString() -> String {
        guard let payloadData = self.payload else { return "" }
        
        return SCMessage.payloadRepresentationStringForData(payloadData, contentFormat: inferredContentFormat())
    }
    
    static func payloadRepresentationStringForData(data: NSData, contentFormat: SCContentFormat) -> String {
        if contentFormat.needsStringUTF8Conversion() {
            return (NSString(data: data, encoding: NSUTF8StringEncoding) as? String) ?? "Format Error"
        }
        return String.toHexFromData(data)
    }
}