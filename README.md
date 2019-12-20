SwiftCoAP
=====
**Updated for Swift 4.2**

**NEW:** Download the Client-Implementation **myCoAP** for iOS/watchOS which builds upon this library: [AppStore-Link](https://itunes.apple.com/de/app/mycoap/id1048383045?mt=8)

This project is an implementation of the "Constrained Application Protocol" (CoAP - RFC 7252) in Swift. It is intended for Clients and Servers.
This implementation provides the standard CoAP features (including Caching) along with the extensions:

* Observe
* Block transfer (Block1 and Block2)

A short manual is provided below.
Feedback is highly appreciated!


Want an Objective-C implementation? Checkout [iCoAP](https://github.com/stuffrabbit/iCoAP).

Getting Started
=====

###The Files:
* Copy all files included in the `SwiftCoAP_Library` folder to your Xcode project
* Make sure to add `GCDAsyncUdpSocket.h` to your Objective-C Bridging-File, as this project uses the Objective-C-Library CocoaAsyncSocket for UDP communication

###The Code

This section gives you an impression on how to use the provided data structures.

#### SCMessage

`SCMessage` represents a CoAP message in SwiftCoAP. You can initialize a message with help of the designated initializer as follows: `SCMessage()`. Alternatively, `SCMessage` provides a convenience initializer (`convenience init(code: SCCodeValue, type: SCType, payload: NSData?)`) that lets you create an instance the following way: 

```swift
SCMessage(code: SCCodeValue(classValue: 0, detailValue: 01)!, type: .Confirmable, payload: "test".dataUsingEncoding(NSUTF8StringEncoding))
```
* The CoAP type is represented as `SCType` of type enum (refer to source code) 
* The CoAP code is represented as a struct named `SCCodeValue`. The struct lets you apply the CoAP code syntax c.dd (e.g. `SCCodeValue(classValue: 0, detailValue: 01)` equals `0.01` (note that this is a failable initializer, which fails when invalid class values (greater 7) or detail values (greater 31) are passed as arguments)).
* The CoAP options are represented as Dictionary. The option number represents the key (as Int) and the respective value pair represents an Array with NSData objects (in case that the same option is present multiple times). To add an option safely, it is recommended to use the provided `addOption(option: Int, data: NSData)` method.

* Checkout the source code and its comments for more information

#### SCClient

This class represents a CoAP client, which can be initialized with the given designated initializer: `init(delegate: SCClientDelegate?)`.

##### Properties

You can modify the following properties of an `SCClient` object to alter its behavior:

* `sendToken: Bool` (default `true`) If true, a randomized token with at least 4 bytes length is generated upon transmission
* `autoBlock1SZX: UInt?` (default `2`) If not nil, Block1 transfer will be used automatically when the payload size exceeds the value 2^(autoBlock1SZX +4). Valid Values: 0-6
* `httpProxyingData: (hostName: String, port: UInt16)?` (default `nil`) If not nil, all message will be sent via http to the given proxy address
* `cachingActive: Bool` (default `false`) If true, caching is activiated

Send a message by calling the method `sendCoAPMessage(message: SCMessage, hostName: String, port: UInt16)` and implement the provided `SCClientDelegate` protocol to receive callbacks. This should be it.

##### Example

```swift
let m = SCMessage(code: SCCodeValue(classValue: 0, detailValue: 01), type: .Confirmable, payload: "test".dataUsingEncoding(NSUTF8StringEncoding))
m.addOption(SCOption.UriPath.rawValue, data: "test".dataUsingEncoding(NSUTF8StringEncoding)!)
let coapClient = SCClient(delegate: self)
coapClient.sendCoAPMessage(m, hostName: "coap.me", port: 5683)
```
##### Other Methods

* `cancelObserve()` Cancels observe directly, sending the previous message with an Observe-Option Value of 1. Only effective, if the previous message initiated a registration as observer with the respective server.
* `closeTransmission()` Closes the transmission. It is recommended to call this method anytime you do not expect to receive a response any longer.

##### HTTP-Proxying

The class `SCClient` gives you the opportunity to send a message as HTTP via a proxy. Just add the following line after initiating an `SCClient`object:
```swift
coapClient.httpProxyingData = ("localhost", 5683)
```
The Options of the CoAP-Message are sent in the HTTP-Header. It is required that the Proxy returns the CoAP-Type in the Header of HTTP-Response as well. The respective Header-Field is `COAP_TYPE`.
The Request-URI has the following Format: `http://proxyHost:proxyPort/coapHost:coapPort`
An Example: Sending your message to the CoAP-Server `coap.me` with the Port `5683` via a HTTP-Proxy located at `localhost:9292`, lets the SwiftCoAP library compose the follwoing Request-URI: `http://localhost:9292/coap.me:5683`

##### Custom Transport Layer Functionality

`SCClient` encapsulates the CoAP transport layer functionality into a separate object which implements the `SCCoAPTransportLayerProtocol` protocol. `SCClient` uses the provided `SCCoAPUDPTransportLayer` class by default, which uses UDP. However, if you want to replace it with your own class just do the following steps:

* Create a custom class and adopt the SCCoAPTransportLayerProtocol
* Pass an object of your class to the init method of SCClient: `init(delegate: SCClientDelegate?, transportLayerObject: SCCoAPTransportLayerProtocol)`
* `SCClient` will set itself as a delegate of your class and notify you through the methods of `SCCoAPTransportLayerProtocol` when e.g. a data needs to be sent.
* Whenever you receive a response to data you have sent, call methods of the protocol `SCCoAPTransportLayerDelegate` on your property `transportLayerDelegate` which will hold a weak reference to the resepective object of type `SCClient`(reference is automatically set through SCClient).
* Checkout the source code and the implementation of the class `SCCoAPUDPTransportLayer`, to see the functionality in action.

An (real) example where using a custom transport layer functionality would be helpful:
You cannot use UDP, e.g. when you bring this library to WatchOS 2. As UDP communcation is not available on this OS you can use WatchConnectiviy as transport layer object for your `SCClient` and let the iPhone execute the UDP sendings. 
#### SCServer

This class represents a CoAP server, which can be initialized with the standard designated initializer `init()`. The given convenience initializer `init?(port: UInt16)` initializes a server instance and automatically starts listening on the given port. This initialization can fail if a UDP-socket error occurs.

##### Properties

You can modify the following properties of an `SCServer` object to alter its behavior:

* `autoBlock2SZX: UInt?` (default `nil`) If not nil, Block2 transfer will be used automatically in responses when the payload size exceeds the value 2^(autoBlock1SZX +4). Valid Values: 0-6
* `resources: [SCResourceModel]` Array of `SCResourceModel` objects which represent a resource of the server (see below)
* `autoWellKnownCore: Bool` (default `true`) If set to `true`, the server will automatically provide responses for the resource `well-known/core` with its current resources.
##### Methods

* `start(port: UInt16 = 5683) -> Bool` Starts the server manually on the given port
* `close()` Closes Udp socket listening
* `reset()` Resets the context of the server (including added resources, cached message contexts, registered observers for resources and data uploads for Block1)
* `didCompleteAsynchronousRequestForOriginalMessage(message: SCMessage, resource: SCResourceModel, values:(statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!, locationUri: String!))` Call this method when your resource is ready to process a separate response. The concerned resource must return true for the method `willHandleDataAsynchronouslyForGet(...)`. It is necessary to pass the original message and the resource (both received in `willHandleDataAsynchronouslyForGet`) so that the server is able to retrieve the current context. Additionay, you have to pass the typical `values` tuple which form the response (as described in `SCResourceModel`)
* `updateRegisteredObserversForResource(resource: SCResourceModel)` Call this method when the given resource has updated its data representation in order to notify all registered observers (and has `observable` set to `true`).

#### Resource representation `SCResourceModel`

SwiftCoAP provides the base class `SCResourceModel` to represent a CoAP resource in the server implementation. To create your own resources with custom behavior, you just have to subclass `SCResourceModel`. You must use the designated initializer `init(name: String, allowedRoutes: UInt)` which requires you to set the name and the routes (GET, POST, PUT, DELETE) which you want to support (see explanation below). 

##### Resource properties
`SCResourceModel` has the following properties which can be modified/set on initialization:
* `name: String` The name of the resource
* `allowedRoutes: UInt` Bitmask of allowed routes (see `SCAllowedRoutes` enum) (you can pass for example `SCAllowedRoute.Get.rawValue | SCAllowedRoute.Post.rawValue` to support GET and POST)
* `maxAgeValue: UInt!` (default `nil`) If not nil, every response will contain the provided MaxAge value
* `etag: NSData!` (default `nil` and read-only) If not nil, every response will contain the provided eTag. The etag is generated automatically whenever you update the value `dataRepresentation` of the resource (is represented as hashvalue of your data representation).
* `dataRepresentation: NSData!` The current data representation of the resource. Needs to stay up to date
* `observable: Bool` (default false) If true, a response will contain the Observe option, and endpoints will be able to register as observers in `SCServer`. Call `updateRegisteredObserversForResource(self)`, anytime the value of your `dataRepresentation` changes.

##### Resource methods
The following methods are used for data reception of your allowed routes. SCServer will call the appropriate message upon the reception of a reqeuest. Override the respective methods, which match your allowedRoutes.
 
 SCServer passes a `queryDictionary` containing the URI query content (e.g `["user_id": "23"]`) and all options contained in the respective request. The POST and PUT methods provide the message's payload as well. 
 Please, refer to the example resources in the `SwiftCoAPServerExample` project for implementation examples.

* `willHandleDataAsynchronouslyForRoute(route: SCAllowedRoute, queryDictionary: [String : String], options: [Int : [NSData]], originalMessage: SCMessage) -> Bool` This method lets you decide whether the current request shall be processed asynchronously, i.e. if `true` will be returned, an empty ACK will be sent, and you can provide the actual content in a separate response by calling the servers `didCompleteAsynchronousRequestForOriginalMessage(...)`. Note: `dataForGet(...)`, `dataForPost(...)`, etc. will not be called additionally if you return `true`.

The following methods require data for the given routes GET, POST, PUT, DELETE and must be overriden if needed. If you return `nil`, the server will respond with a *Method not allowed* error code (Make sure that you have set the allowed routes in the `allowedRoutes` bitmask property).
You have to return a tuple with a statuscode, optional payload, optional content format for your provided payload and (in case of POST and PUT) an optional locationURI.
* `dataForGet(#queryDictionary: [String : String], options: [Int : [NSData]]) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!)?`
* `dataForPost(#queryDictionary: [String : String], options: [Int : [NSData]], requestData: NSData?) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!, locationUri: String!)?`
* `dataForPut(#queryDictionary: [String : String], options: [Int : [NSData]], requestData: NSData?) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!, locationUri: String!)?`
* `dataForDelete(#queryDictionary: [String : String], options: [Int : [NSData]]) -> (statusCode: SCCodeValue, payloadData: NSData?, contentFormat: SCContentFormat!)?`

##### Server with Resources Example
```swift
let server = SCServer(port: 5683)
        
let resource = TestResourceModel(name: "test", allowedRoutes: SCAllowedRoute.Get.rawValue | SCAllowedRoute.Post.rawValue | SCAllowedRoute.Put.rawValue | SCAllowedRoute.Delete.rawValue, 
text: "This is a very long description text, I hope that all of you will like it")

server?.resources.append(resource)
server?.delegate = self
```

**Don't hesitate to contact me if something is unclear!**

Examples:
=====
Make sure to take a look at the examples, which show the library in action. Let me know if you have questions, or other issues.


Used Libraries:
=====
 This version uses the public domain licensed CocoaAsyncSocket library 
 for UDP-socket networking.
 [Click here](https://github.com/robbiehanson/CocoaAsyncSocket) for more information.
