SwiftCoAP
=====

This project is an implementation of the "Constrained Application Protocol" (CoAP) in Swift for Clients and Servers (coming soon).
This implementation provides the standard CoAP (including Caching) features along with the extensions
The current version has besides the standard CoAP features the following additions:
* Observe
* Block transfer (Block1 and Block2)

Feedback is highly appreciated!

Getting Started
=====

###The Files:
* Copy all files included in the `SwiftCoAP_Library` folder to your XCode project.
* Make sure to add `GCDAsyncUdpSocket.h` in your Objective-C Bridging-File, as this project uses the Objective-C-Library CocoaAsyncSocket for UDP communication

###The Code

This section gives you an impression on how to use the provided data structures.

#### SCMessage

An `SCMessage` represents a CoAP message in SwiftCoAP. You can initialize a message with help of the designated initializer as follows: `SCMessage()`. Alternatively, `SCMessage` provides a convenience initializer (`convenience init(code: SCCodeValue, type: SCType, payload: NSData?)`) that lets you create an instance the following way: 

```swift
SCMessage(code: SCCodeValue(classValue: 0, detailValue: 01), type: .Confirmable, payload: "test".dataUsingEncoding(NSUTF8StringEncoding))
```
* The CoAP type is represented as `SCType` of type enum 
* The CoAP code is represented as a struct named `SCCodeValue`. The struct lets you apply the CoAP code syntax c.dd (e.g. SCCodeValue(classValue: 0, detailValue: 01) equals 0.01) easily.
* The CoAP options are represented as Dictionary. The option number represents the key (as Int) and the respective value pair represents an Array with NSData objects (in case that the same option is present multiple times). To add an option safely, it is recommended to use the provided `addOption(option: Int, data: NSData)` method.

* Checkout the source code and its comments for more information

#### SCClient

This class represents a CoAP-Client, which can be initialized with the given designated initializer: `init(delegate: SCClientDelegate?)`
You can modify the following properties of an `SCClient` object to alter its behavior:

* `sendToken: Bool` (default `true`) Generates a randomized token with at least 4 bytes length
* `autoBlock1SZX: UInt?` If not nil, Block1 transfer will be used automatically when the payload size exceeds the value 2^(autoBlock1SZX +4)
* `httpProxyingData: (hostName: String, port: UInt16)?` If not nil, all message will be sent via http to the given proxy address
* `cachingActive: Bool` (default `false`) Activiates Caching

Send a message by calling the method `sendCoAPMessage(message: SCMessage, hostName: String, port: UInt16)`. Implement the provided `SCClientDelegate` protocol. This should be it.

##### Example

```swift
var m = SCMessage(code: SCCodeValue(classValue: 0, detailValue: 01), type: .Confirmable, payload: "test".dataUsingEncoding(NSUTF8StringEncoding))
var coapClient = SCClient(delegate: self)
coapClient.sendCoAPMessage(m, hostName: "coap.me", port: 5683)
```
##### Other Methods

* `cancelObserve()` Cancels observe directly, sending the previous message with an Observe-Option Value of 1. Only effective, if the previous message initiated a registration as observer with the respective server.
* `closeTransmission()` Closes the transmission. It is recommended to call this method anytime you do not expect to receive a response any longer.

Used Libraries:
=====
 This version uses the public domain licensed CocoaAsyncSocket library 
 for UDP-socket networking.
 See more on https://github.com/robbiehanson/CocoaAsyncSocket
