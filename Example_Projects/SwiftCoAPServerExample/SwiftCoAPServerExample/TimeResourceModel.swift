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
            self.dataRepresentation = myText.data(using: String.Encoding.utf8) //update observable Data anytime myText is changed
        }
    }
    weak var server: SCServer!
    var observeTimer: Timer!
    //
        
    init(name: String, allowedRoutes: UInt, text: String, server: SCServer!) {
        self.myText = text
        self.server = server
        super.init(name: name, allowedRoutes: allowedRoutes)
        //Starting Updates for Observe
        self.observeTimer = Timer(timeInterval: 5.0, target: self, selector: #selector(TimeResourceModel.updateObservableData), userInfo: nil, repeats: true)
        RunLoop.current.add(self.observeTimer, forMode: RunLoop.Mode.common)
        self.observable = true
        self.dataRepresentation = myText.data(using: String.Encoding.utf8)
    }
    
    @objc func updateObservableData() {
        myText = "Observe Time: \(Date())"
        server.updateRegisteredObserversForResource(self)
    }
    
    override func dataForGet(queryDictionary: [String : String], options: [Int : [Data]]) -> (statusCode: SCCodeValue, payloadData: Data?, contentFormat: SCContentFormat?)? {
        return (SCCodeValue(classValue: 2, detailValue: 05)!, myText.data(using: String.Encoding.utf8), .plain)
    }
}
