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
        myServer?.resources.append(TestResourceModel(name: "test", allowedRoutes: SCAllowedRoute.Get.rawValue | SCAllowedRoute.Post.rawValue | SCAllowedRoute.Put.rawValue | SCAllowedRoute.Delete.rawValue, text: "This is a very long description text, I hope that all of you will like it"))
        myServer?.resources.append(TimeResourceModel(name: "time", allowedRoutes: SCAllowedRoute.Get.rawValue, text: "Current Date Time: \(NSDate())", server: myServer))
        myServer?.resources.append(SeparateResourceModel(name: "separate", allowedRoutes: SCAllowedRoute.Get.rawValue, text: "Delayed answer...", server: myServer))

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
        print("Failed with Error \(error.localizedDescription)")
    }
    
    func swiftCoapServer(server: SCServer, didHandleRequestWithCode requestCode: SCCodeValue, forResource resource: SCResourceModel, withResponseCode responseCode: SCCodeValue) {
        tableView.reloadData()
        print("Did Handle Request with request code: \(requestCode.toString()) for resource \(resource.name) with response code: \(responseCode.toString())")
    }
    
    func swiftCoapServer(server: SCServer, didRejectRequestWithCode requestCode: SCCodeValue, forPath path: String, withResponseCode responseCode: SCCodeValue) {
        print("Did Reject Request with request code: \(requestCode.toString()) for resource path \(path) with response code: \(responseCode.toString())")
    }
    
    func swiftCoapServer(server: SCServer, didSendSeparateResponseMessage: SCMessage, number: Int) {
        print("Server sent separate Response message)")
    }
    
    func swiftCoapServer(server: SCServer, willUpdatedObserversForResource resource: SCResourceModel) {
        tableView.reloadData()
        print("Attempting to Update Observers for resource \(resource.name)")
    }
}
