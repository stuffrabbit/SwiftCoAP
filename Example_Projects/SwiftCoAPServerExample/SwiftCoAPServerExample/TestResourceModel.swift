//
//  TestResourceModel.swift
//  SwiftCoAPServerExample
//
//  Created by Wojtek Kordylewski on 25.06.15.
//  Copyright (c) 2015 Wojtek Kordylewski. All rights reserved.
//

import UIKit

class TestResourceModel: SCResourceModel {
    //Individual Properties
    var myText: String {
        didSet {
            self.dataRepresentation = myText.dataUsingEncoding(NSUTF8StringEncoding) //update observable Data anytime myText is changed
        }
    }
    //
    
    init(name: String, allowedRoutes: UInt, text: String) {
        self.myText = text
        super.init(name: name, allowedRoutes: allowedRoutes)
        self.dataRepresentation = myText.dataUsingEncoding(NSUTF8StringEncoding)
    }
    
    override func dataForGet(queryDictionary queryDictionary: [String : String], options: [Int : [NSData]]) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!)? {
        return (SCCodeValue(classValue: 2, detailValue: 05)!, myText.dataUsingEncoding(NSUTF8StringEncoding), SCContentFormat.Plain)
    }
    
    override func dataForPost(queryDictionary queryDictionary: [String : String], options: [Int : [NSData]], requestData: NSData?) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!, locationUri: String!)? {
        if let data = requestData, string = NSString(data: data, encoding: NSUTF8StringEncoding) as? String{
            myText = string
            return (SCCodeSample.Created.codeValue(), "Data created successfully".dataUsingEncoding(NSUTF8StringEncoding), SCContentFormat.Plain, self.name)
        }
        return (SCCodeSample.Forbidden.codeValue(), "Invalid Data sent".dataUsingEncoding(NSUTF8StringEncoding), SCContentFormat.Plain, nil)
    }
    
    override func dataForPut(queryDictionary queryDictionary: [String : String], options: [Int : [NSData]], requestData: NSData?) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!, locationUri: String!)? {
        if let data = requestData, string = NSString(data: data, encoding: NSUTF8StringEncoding) as? String{
            myText += string
            return (SCCodeSample.Changed.codeValue(), "Update Successful".dataUsingEncoding(NSUTF8StringEncoding), SCContentFormat.Plain, self.name)
        }
        return (SCCodeSample.Forbidden.codeValue(), "Invalid Data sent".dataUsingEncoding(NSUTF8StringEncoding), SCContentFormat.Plain, nil)
    }
    
    override func dataForDelete(queryDictionary queryDictionary: [String : String], options: [Int : [NSData]]) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!)? {
        myText = ""
        return (SCCodeSample.Delete.codeValue(), "Deleted".dataUsingEncoding(NSUTF8StringEncoding), SCContentFormat.Plain)
    }
}
