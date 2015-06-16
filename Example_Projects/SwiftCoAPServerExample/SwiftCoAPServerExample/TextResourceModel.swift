//
//  TextResourceModel.swift
//  SwiftCoAPServerExample
//
//  Created by Wojtek Kordylewski on 12.06.15.
//  Copyright (c) 2015 Wojtek Kordylewski. All rights reserved.
//

import UIKit

class TextResourceModel: NSObject {
    
    //Individual Properties
    var myText: String
    weak var server: SCServer!

    //Protocol Properties
    let name: String
    let allowedRoutes: UInt = SCAllowedRoute.Get.rawValue | SCAllowedRoute.Post.rawValue
    
    var maxAgeValue: UInt!
    var etag: NSData!
    
    init(name: String, text: String, server: SCServer!) {
        self.name = name
        self.myText = text
        self.server = server
    }

    func delay(delay:Double, closure:()->()) {
        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                Int64(delay * Double(NSEC_PER_SEC))
            ),
            dispatch_get_main_queue(), closure)
    }
}

extension TextResourceModel: SCResourceModel {
    func willHandleDataAsynchronouslyForGet(#queryDictionary: [String : String], options: [Int : [NSData]], originalMessage: SCMessage) -> Bool {
        delay(1.0) {
            self.server.didCompleteAsynchronousRequestForOriginalMessage(originalMessage, resource: self, values: (SCCodeValue(classValue: 2, detailValue: 05), self.myText.dataUsingEncoding(NSUTF8StringEncoding), SCContentFormat.Plain))
        }
        return true
    }
    
    func dataForGet(#queryDictionary: [String : String], options: [Int : [NSData]]) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!)? {
        return (SCCodeValue(classValue: 2, detailValue: 05), myText.dataUsingEncoding(NSUTF8StringEncoding), SCContentFormat.Plain)
    }
    
    func dataForPost(#queryDictionary: [String : String], options: [Int : [NSData]], requestData: NSData?) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!, locationUri: String!)? {
        if let data = requestData, string = NSString(data: data, encoding: NSUTF8StringEncoding) as? String{
            myText = string
            return (SCCodeSample.Changed.codeValue(), "Update Successful".dataUsingEncoding(NSUTF8StringEncoding), SCContentFormat.Plain, "text")
        }
        return (SCCodeSample.Forbidden.codeValue(), "Invalid Data sent".dataUsingEncoding(NSUTF8StringEncoding), SCContentFormat.Plain, nil)
    }
    
    func dataForPut(#queryDictionary: [String : String], options: [Int : [NSData]], requestData: NSData?) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!, locationUri: String!)? {
        return nil
    }
    
    func dataForDelete(#queryDictionary: [String : String], options: [Int : [NSData]]) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!)? {
        return nil
    }
}
