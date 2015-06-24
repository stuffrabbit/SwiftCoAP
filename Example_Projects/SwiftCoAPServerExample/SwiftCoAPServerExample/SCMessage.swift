//
//  SCMessage.swift
//  SwiftCoAP
//
//  Created by Wojtek Kordylewski on 22.04.15.
//  Copyright (c) 2015 Wojtek Kordylewski. All rights reserved.
//

import UIKit


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
            return "RES"
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
        case "RES":
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
    
    enum Format {
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
    
    func needsStringConversion() -> Bool {
        switch self {
        case .OctetStream, .EXI, .CBOR:
            return true
        default:
            return false
        }
    }
}


//MARK:
//MARK: SC Code Value struct: Represents the CoAP code. You can easily apply the CoAP code syntax c.dd (e.g. SCCodeValue(classValue: 0, detailValue: 01) equals 0.01)

struct SCCodeValue: Equatable {
    let classValue: UInt8
    let detailValue: UInt8
    
    func toRawValue() -> UInt8? {
        if classValue > 0b111 || detailValue > 0b11111 { return nil }

        return classValue << 5 + detailValue
    }
    
    static func fromRawValue(value: UInt8) -> SCCodeValue {
        let firstBits: UInt8 = value >> 5
        let lastBits: UInt8 = value & 0b00011111
        return SCCodeValue(classValue: firstBits, detailValue: lastBits)
    }
    
    func toCodeSample() -> SCCodeSample? {
        if let raw = toRawValue(), code = SCCodeSample(rawValue: Int(raw)) {
            return code
        }
        return nil
    }
    
    static func fromCodeSample(code: SCCodeSample) -> SCCodeValue {
        return fromRawValue(UInt8(code.rawValue))
    }
    
    func toString() -> String? {
        if classValue > 0b111 || detailValue > 0b11111 { return nil }

        return String(format: "%i.%02d", classValue, detailValue)
    }
    
    func requestString() -> String? {
        switch self {
        case SCCodeValue(classValue: 0, detailValue: 01):
            return "GET"
        case SCCodeValue(classValue: 0, detailValue: 02):
            return "POST"
        case SCCodeValue(classValue: 0, detailValue: 03):
            return "PUT"
        case SCCodeValue(classValue: 0, detailValue: 04):
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
        var byteLength = UInt(ceil(log2(Double(self + 1)) / 8))
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
//MARK: Resource Implementation, used for SCServer

class SCResourceModel: NSObject {
    let name: String // Name of the resource
    let allowedRoutes: UInt // Bitmask of allowed routes (see SCAllowedRoutes enum)
    var maxAgeValue: UInt! // If not nil, every response will contain the provided MaxAge value
    var etag: NSData! // If not nil, every response will contain the provided eTag
    var dataRepresentation: NSData! // The current data representation of the resource. Needs to stay up to date
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
    func willHandleDataAsynchronouslyForGet(#queryDictionary: [String : String], options: [Int : [NSData]], originalMessage: SCMessage) -> Bool { return false }
    
    //The following methods require data for the given routes GET, POST, PUT, DELETE and must be overriden if needed. If you return nil, the server will respond with a "Method not allowed" error code (Make sure that you have set the allowed routes in the "allowedRoutes" bitmask property).
    //You have to return a tuple with a statuscode, optional payload, optional content format for your provided payload and (in case of POST and PUT) an optional locationURI.
    func dataForGet(#queryDictionary: [String : String], options: [Int : [NSData]]) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!)? { return nil }
    func dataForPost(#queryDictionary: [String : String], options: [Int : [NSData]], requestData: NSData?) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!, locationUri: String!)? { return nil }
    func dataForPut(#queryDictionary: [String : String], options: [Int : [NSData]], requestData: NSData?) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!, locationUri: String!)? { return nil }
    func dataForDelete(#queryDictionary: [String : String], options: [Int : [NSData]]) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!)? { return nil }
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
    
    var code: SCCodeValue = SCCodeValue(classValue: 0, detailValue: 0) //Code value is Empty by default
    var type: SCType = .Confirmable //Type is CON by default
    var payload: NSData? //Add a payload (optional)
    var blockBody: NSData? //Helper for Block1 tranmission. Used by SCClient, modification has no effect
    
    lazy var options = [Int: [NSData]]() //CoAP-Options. It is recommend to use the addOption(..) method to add a new option.

    
    //The following properties are modified by SCClient/SCServer. Modification has no effect and is therefore not recommended
    var hostName: String?
    var port: UInt16?
    var addressData: NSData?
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
            var firstSet = Set(options.keys)
            var secondSet = Set(message.options.keys)
            
            var exOr = firstSet.exclusiveOr(secondSet)
            
            for optNo in exOr {
                if !(SCOption.isNumberNoCacheKey(optNo)) { return false }
            }
            
            var interSect = firstSet.intersect(secondSet)
            
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
        var copiedMessage = SCMessage(code: message.code, type: message.type, payload: message.payload)
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
                var expirationDate = timeStamp!.dateByAddingTimeInterval(Double(value))
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
        
        var tokenLength = Int(ceil(log2(Double(token + 1)) / 8))
        if tokenLength > 8 {
            return nil
        }
        
        if let codeRawValue = code.toRawValue() {
            let firstByte: UInt8 = UInt8((SCMessage.kCoapVersion << 6) | (type.rawValue << 4) | tokenLength)
            var actualMessageId: UInt16 = messageId ?? 0
            var byteArray: [UInt8] = [firstByte, codeRawValue, UInt8(actualMessageId >> 8), UInt8(actualMessageId & 0xFF)]
            resultData = NSMutableData(bytes: &byteArray, length: byteArray.count)
        }
        else {
            return nil //Format Error
        }

        if tokenLength > 0 {
            var tokenByteArray = [UInt8]()
            for var i = 0; i < tokenLength; i++ {
                tokenByteArray.append(UInt8(((token) >> UInt64((tokenLength - i - 1) * 8)) & 0xFF))
            }
            resultData.appendBytes(&tokenByteArray, length: tokenLength)
        }
        
        var sortedOptions = sorted(options) {
            $0.0 < $1.0
        }
        
        var previousDelta = 0
        for (key, valueArray) in sortedOptions {
            var optionDelta = key - previousDelta
            previousDelta += optionDelta
            
            for value in valueArray {
                var optionFirstByte: UInt8
                var extendedDelta: NSData?
                var extendedLength: NSData?
                
                if optionDelta >= Int(kOptionTwoBytesExtraValue) + 0xFF {
                    optionFirstByte = kOptionTwoBytesExtraValue << 4
                    var extendedDeltaValue: UInt16 = UInt16(optionDelta) - (UInt16(kOptionTwoBytesExtraValue) + 0xFF)
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
                    var extendedLengthValue: UInt16 = UInt16(value.length) - (UInt16(kOptionTwoBytesExtraValue) + 0xFF)
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
        return resultData
    }
    
    static func fromData(data: NSData) -> SCMessage? {
        if data.length < 4 { return nil }
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
        var message = SCMessage()
        message.type = type!
        message.code = SCCodeValue.fromRawValue(headerBytes[1])
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
                var optLength = nextByte & 0xF
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
        var urlRequest = NSMutableURLRequest()
        if code != SCCodeSample.Get.codeValue() {
            urlRequest.HTTPMethod = code.requestString()!
        }
        
        for (key, valueArray) in options {
            for value in valueArray {
                var fieldString: String
                if let optEnum = SCOption(rawValue: key) {
                    switch optEnum.format() {
                    case .String:
                        fieldString = NSString(data: value, encoding: NSUTF8StringEncoding) as? String ?? ""
                    case .Empty:
                        fieldString = ""
                    default:
                        fieldString = String(UInt.fromData(value))
                    }
                }
                else {
                    fieldString = ""
                }
                
                if let optionName = SCOption(rawValue: key)?.toString().uppercaseString {
                    urlRequest.addValue(String(fieldString), forHTTPHeaderField: optionName)
                }
            }
        }
        urlRequest.HTTPBody = payload
        
        return urlRequest
    }
    
    static func fromHttpUrlResponse(urlResponse: NSHTTPURLResponse, data: NSData!) -> SCMessage {
        var message = SCMessage()
        message.payload = data
        message.code = SCCodeValue.fromRawValue(UInt8(urlResponse.statusCode & 0xff))
        if let typeString = urlResponse.allHeaderFields[SCMessage.kProxyCoAPTypeKey] as? String, type = SCType.fromShortString(typeString) {
            message.type = type
        }
        for opt in SCOption.allValues {
            if let optValue = urlResponse.allHeaderFields["HTTP_\(opt.toString().uppercaseString)"] as? String {
                var optValueData: NSData
                switch opt.format() {
                case .Empty:
                    optValueData = NSData()
                case .String:
                    optValueData = optValue.dataUsingEncoding(NSUTF8StringEncoding)!
                default:
                    if let intVal = optValue.toInt() {
                        var byteArray = UInt(intVal).toByteArray()
                        optValueData = NSData(bytes: &byteArray, length: byteArray.count)
                    }
                    else {
                        optValueData = NSData()
                    }
                }
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
                if let queryString = NSString(data: queryData, encoding: NSUTF8StringEncoding), splitArray = queryString.componentsSeparatedByString("=") as? [String] where splitArray.count == 2 {
                    resultDict[splitArray.first!] = splitArray.last!
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
}