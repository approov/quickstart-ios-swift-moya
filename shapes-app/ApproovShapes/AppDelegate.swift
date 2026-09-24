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

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Initialize Approov once, before a view can create a Moya provider.
        // ApproovConfig in Info.plist holds the account configuration from `approov sdk -getConfigString`
        // (leave it empty for the unprotected first step). Do not commit a real configuration.
        let config = Bundle.main.object(forInfoDictionaryKey: "ApproovConfig") as? String ?? ""
        // ApproovMessageSigning (Boolean) enables installation message signing; it needs a configuration.
        let signing = Bundle.main.object(forInfoDictionaryKey: "ApproovMessageSigning") as? Bool ?? false
        // A setup failure is logged and does not stop the app: requests are then sent without
        // Approov tokens and the protected backend rejects them.
        ShapesNetworking.initialize(config: config, messageSigning: signing)
        return true
    }
}
