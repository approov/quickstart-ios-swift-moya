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

class ViewController: UIViewController {
    @IBOutlet weak var statusImageView: UIImageView!
    @IBOutlet weak var statusTextView: UILabel!
    var provider: MoyaProvider<MyService>?
    private var currentRequest: Cancellable?
    private var requestID = UUID()

    override func viewDidLoad() {
        super.viewDidLoad()
        do {
            provider = try ShapesNetworking.makeProvider()
        } catch {
            render(ShapesPresentation(message: "Unable to create the network session.", imageName: "confused"))
        }
    }

    @IBAction func checkHello() { request(.Hello) }
    @IBAction func checkShape() {
        guard let target = ShapesNetworking.shapeTarget else {
            render(ShapesPresentation(message: "Network setup failed. Check Approov configuration.", imageName: "confused"))
            return
        }
        request(target)
    }

    private func request(_ target: MyService) {
        guard let provider = provider else {
            render(ShapesPresentation(message: "Network session unavailable.", imageName: "confused"))
            return
        }
        // A late response from an earlier tap must not replace the current result.
        let id = UUID()
        requestID = id
        currentRequest?.cancel()
        let message = target == .Hello ? "Checking connectivity..." :
            (target == .Shape ? "Loading public demo (unprotected)..." : "Checking app authenticity...")
        render(ShapesPresentation(message: message,
                                  imageName: "approov"))
        currentRequest = provider.request(target, callbackQueue: .main) { [weak self] result in
            guard let self = self, self.requestID == id else { return }
            self.render(ShapesPresentation.make(target: target, result: result))
        }
    }

    private func render(_ presentation: ShapesPresentation) {
        statusImageView.image = UIImage(named: presentation.imageName)
        statusTextView.text = presentation.message
    }

    deinit { currentRequest?.cancel() }
}
