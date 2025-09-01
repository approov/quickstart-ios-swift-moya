// MIT License
//
// Copyright (c) 2016-present, Approov Ltd.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files
// (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge,
// publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
// subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR
// ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH
// THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import UIKit
import Moya

// *** UNCOMMENT IF USING APPROOV
//import ApproovSession

class ViewController: UIViewController {
    @IBOutlet weak var statusImageView: UIImageView!
    @IBOutlet weak var statusTextView: UILabel!
    var provider : MoyaProvider<MyService>!
    // *** UNCOMMENT TO USE APPROOV
//        let session = ApproovSession();
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
                provider = MoyaProvider<MyService>();
        
        // *** UNCOMMENT TO USE APPROOV
//                provider = MoyaProvider<MyService>(session: session!)
        
        
        
        
        // *** UNCOMMENT TO USE APPROOV
//               try! ApproovService.initialize(config: "<enter-your-config-string>")
        
        // *** UNCOMMENT IF USING APPROOV SECRETS PROTECTION
        //ApproovService.addSubstitutionHeader(header: "Api-Key", prefix: nil)
        
        //*** UNCOMMENT THE LINES BELOW FOR APPROOV USING INSTALLATION MESSAGE SIGNING
        //ApproovService.setApproovInterceptorExtensions(
        //    ApproovDefaultMessageSigning().setDefaultFactory(
        //        ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()))
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
    }
    
    // check unprotected hello endpoint
    @IBAction func checkHello() {
        DispatchQueue.main.async {
            self.statusImageView.image = UIImage(named: "approov")
            self.statusTextView.text = "Checking connectivity..."
        }
        var message = "unknown networking error"
        provider.request(.Hello) { result in
            switch result {
            case let .success(response):
                let data = response.data
                let statusCode = response.statusCode
                NSLog("The response is a success : \(statusCode)")
                message = "\(statusCode) : \(data)"
                if statusCode == 200 {
                    message = "\(statusCode) : OK"
                    DispatchQueue.main.async {
                        self.statusImageView.image = UIImage(named: "hello")
                        self.statusTextView.text = message
                    }
                }
                
            case let .failure(error):
                DispatchQueue.main.async {
                    self.statusImageView.image = UIImage(named: "confused")
                    self.statusTextView.text = "\(error)"
                }
            }
        }

        
    }
    @IBAction func checkShape() {
        DispatchQueue.main.async {
            self.statusImageView.image = UIImage(named: "approov")
            self.statusTextView.text = "Checking app authenticity..."
        }
        var message = "unknown networking error"
        var image = UIImage(named: "confused")
        provider.request(.Shape) { result in
            switch result {
            case let .success(response):
                let data = response.data
                let statusCode = response.statusCode
                NSLog("The response is a success : \(statusCode)")
                message = "\(statusCode) : \(data)"
                if statusCode == 200 {
                    do {
                        let json = try JSONSerialization.jsonObject(with: response.data, options: [])
                        let jsonDict = json as? [String: Any]
                        message = (jsonDict!["status"] as? String)!
                        let shape = (jsonDict!["shape"] as? String)!.lowercased()
                        switch shape {
                        case "circle":
                            image = UIImage(named: "circle")
                        case "rectangle":
                            image = UIImage(named: "rectangle")
                        case "square":
                            image = UIImage(named: "square")
                        case "triangle":
                            image = UIImage(named: "triangle")
                        default:
                            message = "\(statusCode): unknown shape '\(shape)'"
                        }
                        DispatchQueue.main.async {
                            self.statusImageView.image = image
                            self.statusTextView.text = message
                        }
                    } catch {
                        print("Error decoding response: \(error)")
                    }
                }
                else {
                    DispatchQueue.main.async {
                        self.statusImageView.image = image
                        self.statusTextView.text = message
                    }
                }
                
            case let .failure(error):
                DispatchQueue.main.async {
                    self.statusImageView.image = UIImage(named: "confused")
                    self.statusTextView.text = "\(error)"
                }
            }
        }

    }
    
    
}




