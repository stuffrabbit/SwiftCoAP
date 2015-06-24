//
//  ExampleViewController.swift
//  SwiftCoAPServerExample
//
//  Created by Wojtek Kordylewski on 12.06.15.
//  Copyright (c) 2015 Wojtek Kordylewski. All rights reserved.
//

import UIKit

class ExampleViewController: UIViewController {

    let myServer: SCServer? = SCServer()
    let kDefaultCellIdentifier = "DefaultCell"

    @IBOutlet weak var tableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        myServer?.resources.append(TextResourceModel(name: "text", allowedRoutes: SCAllowedRoute.Get.rawValue | SCAllowedRoute.Post.rawValue | SCAllowedRoute.Delete.rawValue, text: "This is a very long description text, I hope that all of you will like it"))
        myServer?.resources.append(TimeResourceModel(name: "time", allowedRoutes: SCAllowedRoute.Get.rawValue, text: "Current Date Time: \(NSDate())", server: myServer))
        myServer?.resources.append(SeparateResourceModel(name: "delay", allowedRoutes: SCAllowedRoute.Get.rawValue, text: "Delayed answer...", server: myServer))

        myServer?.delegate = self
        myServer?.autoBlock2SZX = 1
        myServer?.start()

        tableView.contentInset = UIEdgeInsetsMake(64.0, 0, 0, 0)
        tableView.estimatedRowHeight = 44.0
        tableView.rowHeight = UITableViewAutomaticDimension
    }
    
    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        myServer?.close()
    }
}

extension ExampleViewController: UITableViewDataSource {
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return myServer?.resources.count ?? 0
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier(kDefaultCellIdentifier) as! DefaultTableViewCell
        let textResource = myServer!.resources[indexPath.row]
        cell.nameLabel.text = textResource.name
        cell.detailLabel.text = NSString(data: textResource.dataRepresentation, encoding: NSUTF8StringEncoding) as? String
        return cell
    }
}

extension ExampleViewController: SCServerDelegate {
    func swiftCoapServer(server: SCServer, didFailWithError error: NSError) {
        println("Failed with Error \(error.localizedDescription)")
    }
    
    func swiftCoapServer(server: SCServer, didHandleRequestWithCode code: SCCodeValue, forResource resource: SCResourceModel) {
        tableView.reloadData()
        println("Did Handle Request for resource \(resource.name)")
    }
    
    func swiftCoapServer(server: SCServer, didRejectRequestWithCode requestCode: SCCodeValue, forPath path: String, withResponseCode responseCode: SCCodeValue) {
        println("Did Reject Request for resource path \(path)")
    }
    
    func swiftCoapServer(server: SCServer, didSendSeparateResponseMessage: SCMessage, number: Int) {
        println("Server sent separate Response message)")
    }
    
    func swiftCoapServer(server: SCServer, willUpdatedObserversForResource resource: SCResourceModel) {
        tableView.reloadData()
        println("Attempting to Update Observers for resource \(resource.name)")
    }
}
