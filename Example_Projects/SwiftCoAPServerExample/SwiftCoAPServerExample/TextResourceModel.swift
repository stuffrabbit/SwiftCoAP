//
//  TextResourceModel.swift
//  SwiftCoAPServerExample
//
//  Created by Wojtek Kordylewski on 12.06.15.
//  Copyright (c) 2015 Wojtek Kordylewski. All rights reserved.
//

import UIKit

class TextResourceModel: SCResourceModel {
    
    //Individual Properties
    var myText: String {
        didSet {
            self.observableData = myText.dataUsingEncoding(NSUTF8StringEncoding) //update observable Data anytime myText is changed
        }
    }
    weak var server: SCServer!
    var observeTimer: NSTimer!
    
    init(name: String, allowedRoutes: UInt, text: String, server: SCServer!) {
        self.myText = text
        self.server = server
        super.init(name: name, allowedRoutes: allowedRoutes)
        
        //Starting Updates for Observe
        self.observeTimer = NSTimer(timeInterval: 5.0, target: self, selector: "updateObservableData", userInfo: nil, repeats: true)
        NSRunLoop.currentRunLoop().addTimer(self.observeTimer, forMode: NSRunLoopCommonModes)

        self.observableData = myText.dataUsingEncoding(NSUTF8StringEncoding) //IF not nil, observe is active
    }

    func updateObservableData() {
        myText = "Observe Time: \(NSDate())"
        server.updateRegisteredObserversForResource(self)
    }
    
    func delay(delay:Double, closure:()->()) {
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, Int64(delay * Double(NSEC_PER_SEC))),
            dispatch_get_main_queue(),
            closure
        )
    }
    
    override func willHandleDataAsynchronouslyForGet(#queryDictionary: [String : String], options: [Int : [NSData]], originalMessage: SCMessage) -> Bool {
        return false
        //Insert if you want a separate response
        /*
        delay(6.0) {
            self.server.didCompleteAsynchronousRequestForOriginalMessage(originalMessage, resource: self, values: (SCCodeValue(classValue: 2, detailValue: 05), self.myText.dataUsingEncoding(NSUTF8StringEncoding), SCContentFormat.Plain))
        }
        return true
        */
    }
    
    override func dataForGet(#queryDictionary: [String : String], options: [Int : [NSData]]) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!)? {
        return (SCCodeValue(classValue: 2, detailValue: 05), myText.dataUsingEncoding(NSUTF8StringEncoding), SCContentFormat.Plain)
    }
    
    override func dataForPost(#queryDictionary: [String : String], options: [Int : [NSData]], requestData: NSData?) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!, locationUri: String!)? {
        if let data = requestData, string = NSString(data: data, encoding: NSUTF8StringEncoding) as? String{
            myText = string
            return (SCCodeSample.Changed.codeValue(), "Update Successful".dataUsingEncoding(NSUTF8StringEncoding), SCContentFormat.Plain, "text")
        }
        return (SCCodeSample.Forbidden.codeValue(), "Invalid Data sent".dataUsingEncoding(NSUTF8StringEncoding), SCContentFormat.Plain, nil)
    }
}