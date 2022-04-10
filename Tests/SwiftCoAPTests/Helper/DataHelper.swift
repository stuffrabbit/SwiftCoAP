//
//  File.swift
//  
//
//  Created by Hoang Viet Tran on 07/04/2022.
//

import Foundation

struct DataHelper {
    static func secureRandomData(count: Int) throws -> Data? {
        var bytes = [Int8](repeating: 0, count: count)

        let status = SecRandomCopyBytes(
            kSecRandomDefault,
            count,
            &bytes
        )
        
        if status == errSecSuccess {
            return Data(bytes: bytes, count: count)
        } else {
            return nil
        }
    }
}
