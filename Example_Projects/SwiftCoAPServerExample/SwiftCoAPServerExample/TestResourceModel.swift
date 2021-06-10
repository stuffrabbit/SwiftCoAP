//
//  TestResourceModel.swift
//  SwiftCoAPServerExample
//
//  Created by Wojtek Kordylewski on 25.06.15.
//  Copyright (c) 2015 Wojtek Kordylewski. All rights reserved.
//

import UIKit
import SwiftCoAP

class TestResourceModel: SCResourceModel {
    //Individual Properties
    var myText: String {
        didSet {
            self.dataRepresentation = myText.data(using: String.Encoding.utf8) //update observable Data anytime myText is changed
        }
    }
    //
    
    init(name: String, allowedRoutes: UInt, text: String) {
        self.myText = text
        super.init(name: name, allowedRoutes: allowedRoutes)
        self.dataRepresentation = myText.data(using: String.Encoding.utf8)
    }
    
    override func dataForGet(queryDictionary: [String : String], options: [Int : [Data]]) -> (statusCode: SCCodeValue, payloadData: Data?, contentFormat: SCContentFormat?)? {
        return (SCCodeValue(classValue: 2, detailValue: 05)!, myText.data(using: String.Encoding.utf8), .plain)
    }
    
    override func dataForPost(queryDictionary: [String : String], options: [Int : [Data]], requestData: Data?) -> (statusCode: SCCodeValue, payloadData: Data?, contentFormat: SCContentFormat?, locationUri: String?)? {
        if let data = requestData, let string = NSString(data: data, encoding: String.Encoding.utf8.rawValue) as String?{
            myText = string
            return (SCCodeSample.created.codeValue(), "Data created successfully".data(using: String.Encoding.utf8), .plain, self.name)
        }
        return (SCCodeSample.forbidden.codeValue(), "Invalid Data sent".data(using: String.Encoding.utf8), .plain, nil)
    }
    
    override func dataForPut(queryDictionary: [String : String], options: [Int : [Data]], requestData: Data?) -> (statusCode: SCCodeValue, payloadData: Data?, contentFormat: SCContentFormat?, locationUri: String?)? {
        if let data = requestData, let string = NSString(data: data, encoding: String.Encoding.utf8.rawValue) as String?{
            myText += string
            return (SCCodeSample.changed.codeValue(), "Update Successful".data(using: String.Encoding.utf8), .plain, self.name)
        }
        return (SCCodeSample.forbidden.codeValue(), "Invalid Data sent".data(using: String.Encoding.utf8), .plain, nil)
    }
    
    override func dataForDelete(queryDictionary: [String : String], options: [Int : [Data]]) -> (statusCode: SCCodeValue, payloadData: Data?, contentFormat: SCContentFormat?)? {
        myText = ""
        return (SCCodeSample.deleted.codeValue(), "Deleted".data(using: String.Encoding.utf8), .plain)
    }
}
