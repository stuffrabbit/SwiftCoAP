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
        coapClient = SCClient(delegate: self)
        //coapClient.cachingActive = true
        coapClient.sendToken = true
        coapClient.autoBlock1SZX = 2
        //coapClient.httpProxyingData = ("localhost", 5683)
        
        //Default values, change if you want
        hostTextField.text = "coap.me"
        portTextField.text = "5683"
    }
    
    // MARK: Actions
    
    @IBAction func onClickDelete(sender: AnyObject) {
        textView.text = ""
    }
    
    @IBAction func onClickSendMessage(sender: AnyObject) {
        if sender is UIButton {
            view.endEditing(true)
        }
        var m = SCMessage(code: SCCodeValue(classValue: 0, detailValue: 01)!, type: .Confirmable, payload: "test".dataUsingEncoding(NSUTF8StringEncoding))
        
        if let stringData = uriPathTextField.text.dataUsingEncoding(NSUTF8StringEncoding) {
            m.addOption(SCOption.UriPath.rawValue, data: stringData)
        }
        
        if let port = portTextField.text?.toInt() {
            coapClient.sendCoAPMessage(m, hostName: hostTextField.text, port: UInt16(port))
        }
        else {
            textView.text = "\(textView.text)\nInvalid PORT"
        }
    }
}

extension ExampleViewController: UITextFieldDelegate {
    func textFieldShouldReturn(textField: UITextField) -> Bool {
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
    func swiftCoapClient(client: SCClient, didReceiveMessage message: SCMessage) {
        var payloadstring = ""
        if let pay = message.payload {
            if let string = NSString(data: pay, encoding:NSUTF8StringEncoding) {
                payloadstring = String(string)
            }
        }
        let firstPartString = "Message received with type: \(message.type.shortString())\nwith code: \(message.code.toString()) \nwith id: \(message.messageId)\nPayload: \(payloadstring)"
        var optString = "Options:\n"
        for (key, _) in message.options {
            var optName = "Unknown"
                
            if let knownOpt = SCOption(rawValue: key) {
                optName = knownOpt.toString()
            }

            optString += "\(optName) (\(key))"

            //Add this lines to display the respective option values in the message log
            /*
            for value in valueArray {
                optString += "\(value)\n"
            }
            optString += separatorLine
            */
        }
        textView.text = separatorLine + firstPartString + optString + separatorLine + textView.text
    }
    
    func swiftCoapClient(client: SCClient, didFailWithError error: NSError) {
        textView.text = "Failed with Error \(error.localizedDescription)" + separatorLine + separatorLine + textView.text
    }
    
    func swiftCoapClient(client: SCClient, didSendMessage message: SCMessage, number: Int) {
        textView.text = "Message sent (\(number)) with type: \(message.type.shortString()) with id: \(message.messageId)\n" + separatorLine + separatorLine + textView.text
    }
}