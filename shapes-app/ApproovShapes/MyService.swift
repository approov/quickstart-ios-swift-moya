//
//  MyService.swift
//  ApproovShapes
//
//  Created by Madhav Benoi on 28/08/2025.
//  Copyright © 2025 Approov. All rights reserved.
//
import Foundation
import Moya

// An ordinary Moya target: no Approov code is needed here. ApproovSession adds protection
// to requests for domains added with `approov api -add`.
enum MyService: Equatable {
    case Hello          // v1: connectivity check, no protection
    case Shape          // v1: checks only the API key
    case ProtectedShape // v3: also requires a valid Approov token
    case SignedShape    // v5: also requires an installation message signature
}

extension MyService: TargetType {
    var baseURL : URL { URL(string : "https://shapes.approov.io/")! }
    var task: Task { .requestPlain }

    // Headers declared here are visible to Approov for binding, substitution and signing;
    // headers added later by a Moya plugin are not (see MOYA-OPTIONS.md).
    var headers: [String : String]? {
        return ["Content-type" : "application/json"
                // *** COMMENT IF USING APPROOV SECRETS PROTECTION
                ,"Api-Key" : "yXClypapWNHIifHUWmBIyPFAm"
                // *** UNCOMMENT IF USING APPROOV SECRETS PROTECTION
//                ,"Api-Key" : "shapes_api_key_placeholder"
        ]
    }

    var path: String {
        switch self {
        case .Hello:
            return "v1/hello"
        case .Shape:
            return "v1/shapes"
        case .ProtectedShape:
            return "v3/shapes"
        case .SignedShape:
            return "v5/shapes"
        }
    }

    var method: Moya.Method { .get }
}
