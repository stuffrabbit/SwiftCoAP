//
//  TimeResourceModel.swift
//  SwiftCoAPServerExample
//
//  Created by Wojtek Kordylewski on 23.06.15.
//  Copyright (c) 2015 Wojtek Kordylewski. All rights reserved.
//

import UIKit

class TimeResourceModel: SCResourceModel {
    //Individual Properties
    var myText: String {
        didSet {
            self.dataRepresentation = myText.dataUsingEncoding(NSUTF8StringEncoding) //update observable Data anytime myText is changed
        }
    }
    weak var server: SCServer!
    var observeTimer: NSTimer!
    //
        
    init(name: String, allowedRoutes: UInt, text: String, server: SCServer!) {
        self.myText = text
        self.server = server
        super.init(name: name, allowedRoutes: allowedRoutes)
        //Starting Updates for Observe
        self.observeTimer = NSTimer(timeInterval: 5.0, target: self, selector: "updateObservableData", userInfo: nil, repeats: true)
        NSRunLoop.currentRunLoop().addTimer(self.observeTimer, forMode: NSRunLoopCommonModes)
        self.observable = true
        self.dataRepresentation = myText.dataUsingEncoding(NSUTF8StringEncoding)
    }
    
    func updateObservableData() {
        myText = "Observe Time: \(NSDate())"
        server.updateRegisteredObserversForResource(self)
    }
    
    override func dataForGet(queryDictionary queryDictionary: [String : String], options: [Int : [NSData]]) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!)? {
        return (SCCodeValue(classValue: 2, detailValue: 05)!, myText.dataUsingEncoding(NSUTF8StringEncoding), SCContentFormat.Plain)
    }
}
