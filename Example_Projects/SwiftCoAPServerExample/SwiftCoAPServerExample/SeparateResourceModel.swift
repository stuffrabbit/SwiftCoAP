//
//  SeparateResourceModel.swift
//  SwiftCoAPServerExample
//
//  Created by Wojtek Kordylewski on 23.06.15.
//  Copyright (c) 2015 Wojtek Kordylewski. All rights reserved.
//

import UIKit

class SeparateResourceModel: SCResourceModel {
    //Individual Properties
    var myText: String {
        didSet {
            self.dataRepresentation = myText.dataUsingEncoding(NSUTF8StringEncoding) //update observable Data anytime myText is changed
        }
    }
    weak var server: SCServer!
    //
    
    init(name: String, allowedRoutes: UInt, text: String, server: SCServer!) {
        self.myText = text
        self.server = server
        super.init(name: name, allowedRoutes: allowedRoutes)
        self.dataRepresentation = myText.dataUsingEncoding(NSUTF8StringEncoding)
    }
    
    func delay(delay:Double, closure:()->()) {
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, Int64(delay * Double(NSEC_PER_SEC))),
            dispatch_get_main_queue(),
            closure
        )
    }
    
    override func willHandleDataAsynchronouslyForRoute(route: SCAllowedRoute, queryDictionary: [String : String], options: [Int : [NSData]], originalMessage: SCMessage) -> Bool {
        switch route {
        case .Get:
            delay(6.0) {
                self.server.didCompleteAsynchronousRequestForOriginalMessage(originalMessage, resource: self, values: (SCCodeValue(classValue: 2, detailValue: 05)!, self.myText.dataUsingEncoding(NSUTF8StringEncoding), .Plain, nil))
            }
        case .Post:
            delay(6.0) {
                if let data = originalMessage.payload, string = NSString(data: data, encoding: NSUTF8StringEncoding) as? String {
                    self.myText = string
                    self.server.didCompleteAsynchronousRequestForOriginalMessage(originalMessage, resource: self, values: (SCCodeSample.Created.codeValue(), "Data created successfully".dataUsingEncoding(NSUTF8StringEncoding), .Plain, self.name))
                    
                }
                else {
                    self.server.didCompleteAsynchronousRequestForOriginalMessage(originalMessage, resource: self, values: (SCCodeSample.Forbidden.codeValue(), "Invalid Data sent".dataUsingEncoding(NSUTF8StringEncoding), .Plain, nil))
                }
            }
        case .Put, .Delete:
            return false
        }
        return true
    }
    
    override func dataForDelete(queryDictionary queryDictionary: [String : String], options: [Int : [NSData]]) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!)? {
        myText = "<>"
        return (SCCodeSample.Deleted.codeValue(), "Deleted".dataUsingEncoding(NSUTF8StringEncoding), .Plain)
    }
}
