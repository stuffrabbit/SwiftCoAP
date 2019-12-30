//
//  ExampleViewController.swift
//  SwiftCoAPServerExample
//
//  Created by Wojtek Kordylewski on 12.06.15.
//  Copyright (c) 2015 Wojtek Kordylewski. All rights reserved.
//

import UIKit

class ExampleViewController: UIViewController {

    var myServer: SCServer!
    let kDefaultCellIdentifier = "DefaultCell"

    @IBOutlet weak var tableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if let server = SCServer(delegate: self) {
            server.resources.append(TestResourceModel(name: "test", allowedRoutes: SCAllowedRoute.get.rawValue | SCAllowedRoute.post.rawValue | SCAllowedRoute.put.rawValue | SCAllowedRoute.delete.rawValue, text: "This is a very long description text, I hope that all of you will like it. It should be transmitted via the block2 option by default"))
            server.resources.append(TimeResourceModel(name: "time", allowedRoutes: SCAllowedRoute.get.rawValue, text: "Current Date Time: \(Date())", server: server))
            server.resources.append(SeparateResourceModel(name: "separate", allowedRoutes: SCAllowedRoute.get.rawValue | SCAllowedRoute.post.rawValue | SCAllowedRoute.delete.rawValue, text: "Delayed answer...", server: server))
            
            server.autoBlock2SZX = 1
            myServer = server
        }
        

        tableView.contentInset = UIEdgeInsets.init(top: 64.0, left: 0, bottom: 0, right: 0)
        tableView.estimatedRowHeight = 44.0
        tableView.rowHeight = UITableView.automaticDimension
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        myServer?.close()
    }
}

extension ExampleViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return myServer?.resources.count ?? 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: kDefaultCellIdentifier) as! DefaultTableViewCell
        let textResource = myServer!.resources[indexPath.row]
        cell.nameLabel.text = textResource.name
        cell.detailLabel.text = NSString(data: textResource.dataRepresentation as Data, encoding: String.Encoding.utf8.rawValue) as String?
        return cell
    }
}

extension ExampleViewController: SCServerDelegate {
    func swiftCoapServer(_ server: SCServer, didFailWithError error: NSError) {
        print("Failed with Error \(error.localizedDescription)")
    }
    
    func swiftCoapServer(_ server: SCServer, didHandleRequestWithCode requestCode: SCCodeValue, forResource resource: SCResourceModel, withResponseCode responseCode: SCCodeValue) {
        tableView.reloadData()
        print("Did Handle Request with request code: \(requestCode.toString()) for resource \(resource.name) with response code: \(responseCode.toString())")
    }
    
    func swiftCoapServer(_ server: SCServer, didRejectRequestWithCode requestCode: SCCodeValue, forPath path: String, withResponseCode responseCode: SCCodeValue) {
        print("Did Reject Request with request code: \(requestCode.toString()) for resource path \(path) with response code: \(responseCode.toString())")
    }
    
    func swiftCoapServer(_ server: SCServer, didSendSeparateResponseMessage: SCMessage, number: Int) {
        print("Server sent separate Response message)")
    }
    
    func swiftCoapServer(_ server: SCServer, willUpdatedObserversForResource resource: SCResourceModel) {
        tableView.reloadData()
     //   print("Attempting to Update Observers for resource \(resource.name)")
    }
}
