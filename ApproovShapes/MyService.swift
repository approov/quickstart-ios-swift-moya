//
//  MyService.swift
//  ApproovShapes
//
//  Created by Madhav Benoi on 28/08/2025.
//  Copyright © 2025 Approov. All rights reserved.
//
import Foundation
import Moya

enum MyService {
    case Hello
    case Shape
}


extension MyService: TargetType {
    var baseURL : URL { URL(string : "https://shapes.approov.io/")! }
    var task: Task {
        switch self {
        case .Hello:
            return .requestPlain
        case .Shape:
            
            return .requestPlain
        }
    }
    
    var headers: [String : String]? {
        return ["Content-type" : "application/json"
                ,"Api-Key" : "yXClypapWNHIifHUWmBIyPFAm"
        ]
    }
    
    
    
    var path: String {
        switch self {
        case .Hello:
            return "v1/hello"
        case .Shape:
            return "v1/shapes"
            // *** UNCOMMENT TO USE APPROOV
//            return "v3/shapes"
        }
    }
    
    var method : Moya.Method {
        switch self {
        case .Hello:
            return .get
        case .Shape:
            return .get
        }
        
    }
    
    
}
