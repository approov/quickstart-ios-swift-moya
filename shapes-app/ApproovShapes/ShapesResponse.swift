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
        case .failure:
            return ShapesPresentation(message: "Request failed. Check connectivity and Approov configuration, then retry.",
                                      imageName: "confused")
        case .success(let response):
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
