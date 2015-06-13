//
//  ExampleViewController.swift
//  SwiftCoAPServerExample
//
//  Created by Wojtek Kordylewski on 12.06.15.
//  Copyright (c) 2015 Wojtek Kordylewski. All rights reserved.
//

import UIKit

class ExampleViewController: UIViewController {

    let myServer = SCServer(port: 5683)
    let kDefaultCellIdentifier = "DefaultCell"

    @IBOutlet weak var tableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        myServer?.resources.append(TextResourceModel(name: "text", text: "This is a very long description text, I hope that all of you will like it"))
        myServer?.resources.append(TextResourceModel(name: "text2", text: "Short is better"))
        myServer?.delegate = self
        
        tableView.contentInset = UIEdgeInsetsMake(64.0, 0, 0, 0)
        tableView.estimatedRowHeight = 44.0
        tableView.rowHeight = UITableViewAutomaticDimension
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        tableView.reloadData()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}

extension ExampleViewController: UITableViewDataSource {
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return myServer?.resources.count ?? 0
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier(kDefaultCellIdentifier) as! DefaultTableViewCell
        let textResource = myServer!.resources[indexPath.row] as! TextResourceModel
        cell.nameLabel.text = textResource.name
        cell.detailLabel.text = textResource.myText
        return cell
    }
}

extension ExampleViewController: SCServerDelegate {
    func swiftCoapServer(server: SCServer, didFailWithError error: NSError) {
        println("Could not setup server")
    }
    
    func swiftCoapServer(server: SCServer, didHandleRequestWithCode code: SCCodeValue, forResource resource: SCResourceModel) {
        tableView.reloadData()
        println("DId Handle Request for resource \(resource.name)")
    }
    
    func swiftCoapServer(server: SCServer, didRejectRequestWithCode requestCode: SCCodeValue, forPath path: String, withResponseCode responseCode: SCCodeValue) {
        println("DId Reject Request for resource path \(path)")
    }
}
