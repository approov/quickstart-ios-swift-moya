import Foundation
import Moya

struct ShapesPresentation: Equatable {
    let message: String
    let imageName: String

    private struct ShapeResponse: Decodable {
        let status: String
        let shape: String
    }

    static func make(target: MyService, result: Result<Response, MoyaError>) -> ShapesPresentation {
        switch result {
        // An Approov error (for example, a rejected secret fetch) arrives here wrapped in
        // MoyaError.underlying; see SECRETS-PROTECTION.md#handling-rejections to unwrap it.
        case .failure:
            return ShapesPresentation(message: "Request failed. Check connectivity and Approov configuration, then retry.",
                                      imageName: "confused")
        case .success(let response):
            // Moya reports HTTP errors as success, so check the status. A backend that rejects a
            // missing or invalid Approov token or signature typically answers with a 4xx status.
            guard response.statusCode == 200 else {
                return ShapesPresentation(message: "HTTP \(response.statusCode): request was not accepted.", imageName: "confused")
            }
            if target == .Hello {
                return ShapesPresentation(message: "200 : OK", imageName: "hello")
            }
            guard let decoded = try? JSONDecoder().decode(ShapeResponse.self, from: response.data) else {
                return ShapesPresentation(message: "Invalid response from the Shapes API.", imageName: "confused")
            }
            let shape = decoded.shape.lowercased()
            guard ["circle", "rectangle", "square", "triangle"].contains(shape) else {
                return ShapesPresentation(message: "The Shapes API returned an unknown shape.", imageName: "confused")
            }
            return ShapesPresentation(message: decoded.status, imageName: shape)
        }
    }
}
