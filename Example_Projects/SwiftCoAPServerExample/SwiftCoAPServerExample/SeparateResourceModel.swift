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
            self.dataRepresentation = myText.data(using: String.Encoding.utf8) //update observable Data anytime myText is changed
        }
    }
    weak var server: SCServer!
    //
    
    init(name: String, allowedRoutes: UInt, text: String, server: SCServer!) {
        self.myText = text
        self.server = server
        super.init(name: name, allowedRoutes: allowedRoutes)
        self.dataRepresentation = myText.data(using: String.Encoding.utf8)
    }
    
    func delay(_ delay:Double, closure:@escaping ()->()) {
        DispatchQueue.main.asyncAfter(
            deadline: DispatchTime.now() + Double(Int64(delay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC),
            execute: closure
        )
    }
    
    override func willHandleDataAsynchronouslyForRoute(_ route: SCAllowedRoute, queryDictionary: [String : String], options: [Int : [Data]], originalMessage: SCMessage) -> Bool {
        switch route {
        case .get:
            delay(6.0) {
                self.server.didCompleteAsynchronousRequestForOriginalMessage(originalMessage, resource: self, values: (SCCodeValue(classValue: 2, detailValue: 05)!, self.myText.data(using: String.Encoding.utf8), .plain, nil))
            }
        case .post:
            delay(6.0) {
                if let data = originalMessage.payload, let string = NSString(data: data as Data, encoding: String.Encoding.utf8.rawValue) as String? {
                    self.myText = string
                    self.server.didCompleteAsynchronousRequestForOriginalMessage(originalMessage, resource: self, values: (SCCodeSample.created.codeValue(), "Data created successfully".data(using: String.Encoding.utf8), .plain, self.name))
                    
                }
                else {
                    self.server.didCompleteAsynchronousRequestForOriginalMessage(originalMessage, resource: self, values: (SCCodeSample.forbidden.codeValue(), "Invalid Data sent".data(using: String.Encoding.utf8), .plain, nil))
                }
            }
        case .put, .delete:
            return false
        }
        return true
    }
    
    override func dataForDelete(queryDictionary: [String : String], options: [Int : [Data]]) -> (statusCode: SCCodeValue, payloadData: Data?, contentFormat: SCContentFormat?)? {
        myText = "<>"
        return (SCCodeSample.deleted.codeValue(), "Deleted".data(using: String.Encoding.utf8), .plain)
    }
}
