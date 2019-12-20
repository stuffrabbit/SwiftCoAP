//
//  ExampleViewController.swift
//  SwiftCoAP
//
//  Created by Wojtek Kordylewski on 04.05.15.
//  Copyright (c) 2015 Wojtek Kordylewski. All rights reserved.
//

import UIKit

class ExampleViewController: UIViewController {
    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var hostTextField: UITextField!
    @IBOutlet weak var uriPathTextField: UITextField!
    @IBOutlet weak var portTextField: UITextField!
    
    let separatorLine = "\n-----------------\n"
    
    var coapClient: SCClient!

    override func viewDidLoad() {
        super.viewDidLoad()
        let client = SCClient(delegate: self)
        client.sendToken = true
        client.autoBlock1SZX = 2
        
        //Advanced Settings
        
        //client.cachingActive = true
        //client.httpProxyingData = ("localhost", 5683)
        
        self.coapClient = client
        
        //Default values, change if you want
        hostTextField.text = "coap.me"
        portTextField.text = "5683"
    }
    
    // MARK: Actions
    
    @IBAction func onClickDelete(_ sender: AnyObject) {
        textView.text = ""
    }
    
    @IBAction func onClickSendMessage(_ sender: AnyObject) {
        if sender is UIButton {
            view.endEditing(true)
        }
        let m = SCMessage(code: SCCodeValue(classValue: 0, detailValue: 01)!, type: .confirmable, payload: "test".data(using: String.Encoding.utf8))
        
        if let stringData = uriPathTextField.text?.data(using: String.Encoding.utf8) {
            m.addOption(SCOption.uriPath.rawValue, data: stringData)
        }
        
        if let portString = portTextField.text, let hostString = hostTextField.text, let port = UInt16(portString) {
            coapClient.sendCoAPMessage(m, hostName:hostString,  port: port)
        }
        else {
            textView.text = "\(String(describing: textView.text))\nInvalid PORT"
        }
    }
}

extension ExampleViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        switch textField {
        case hostTextField:
            portTextField.becomeFirstResponder()
        case portTextField:
            uriPathTextField.becomeFirstResponder()
        default:
            uriPathTextField.resignFirstResponder()
            onClickSendMessage(textField)
        }
        return true
    }
}

extension ExampleViewController: SCClientDelegate {
    func swiftCoapClient(_ client: SCClient, didReceiveMessage message: SCMessage) {
        var payloadstring = ""
        if let pay = message.payload {
            if let string = NSString(data: pay as Data, encoding:String.Encoding.utf8.rawValue) {
                payloadstring = String(string)
            }
        }
        let firstPartString = "Message received from \(message.hostName ?? "") with type: \(message.type.shortString())\nwith code: \(message.code.toString()) \nwith id: \(message.messageId ?? 0)\nPayload: \(payloadstring)\n"
        var optString = "Options:\n"
        for (key, _) in message.options {
            var optName = "Unknown"
                
            if let knownOpt = SCOption(rawValue: key) {
                optName = knownOpt.toString()
            }

            optString += "\(optName) (\(key))\n"
        }
        textView.text = separatorLine + firstPartString + optString + separatorLine + textView.text
    }
    
    func swiftCoapClient(_ client: SCClient, didFailWithError error: NSError) {
        textView.text = "Failed with Error \(error.localizedDescription)" + separatorLine + separatorLine + textView.text
    }
    
    func swiftCoapClient(_ client: SCClient, didSendMessage message: SCMessage, number: Int) {
        textView.text = "Message sent (\(number)) with type: \(message.type.shortString()) with id: \(String(describing: message.messageId))\n" + separatorLine + separatorLine + textView.text
    }
}
