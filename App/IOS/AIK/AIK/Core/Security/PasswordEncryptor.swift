import CommonCrypto
import Foundation
import Security

struct EncryptedLoginPassword: Sendable {
    let value: String
    let nonceID: String
}

struct PasswordEncryptor: Sendable {
    func encrypt(
        _ password: String,
        client: APIClient
    ) async throws -> EncryptedLoginPassword {
        async let nonce: NonceResponse = client.get(
            "/crypto/nonce",
            as: NonceResponse.self
        )
        async let publicKey: String = client.get(
            "/crypto/publickey",
            as: String.self
        )
        let (nonceValue, keyValue) = try await (nonce, publicKey)
        let aesKey = randomASCII(count: 32)
        let encryptedPassword = try encryptAES(password, key: aesKey)
        let encryptedKey = try encryptRSA(
            "\(aesKey):\(nonceValue.Nonce)",
            publicKey: keyValue
        )
        return EncryptedLoginPassword(
            value: "\(encryptedKey):\(encryptedPassword)",
            nonceID: nonceValue.NonceId
        )
    }

    private func randomASCII(count: Int) -> String {
        let alphabet = Array(
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        )
        var generator = SystemRandomNumberGenerator()
        return String(
            (0..<count).map { _ in
                alphabet.randomElement(using: &generator)!
            }
        )
    }

    private func encryptAES(_ value: String, key: String) throws -> String {
        let input = Data(value.utf8)
        let keyData = Data(key.padding(toLength: 32, withPad: " ", startingAt: 0).utf8)
        let iv = Data("AreyoumySnowman?".utf8)
        let outputCapacity = input.count + kCCBlockSizeAES128
        var output = Data(count: outputCapacity)
        var outputLength = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            input.withUnsafeBytes { inputBytes in
                keyData.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            kCCKeySizeAES256,
                            ivBytes.baseAddress,
                            inputBytes.baseAddress,
                            input.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else {
            throw APIError.server(String(localized: "error.password_encryption"))
        }
        output.removeSubrange(outputLength..<output.count)
        return output.base64EncodedString()
    }

    private func encryptRSA(_ value: String, publicKey: String) throws -> String {
        let parts = publicKey.split(separator: ".", maxSplits: 1)
        guard parts.count == 2,
              let modulus = Data(base64Encoded: String(parts[0])),
              let exponent = Data(base64Encoded: String(parts[1])) else {
            throw APIError.server(String(localized: "error.public_key"))
        }
        let keyData = ASN1.sequence([
            ASN1.integer(modulus),
            ASN1.integer(exponent),
        ])
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: modulus.count * 8,
        ]
        var keyError: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(
            keyData as CFData,
            attributes as CFDictionary,
            &keyError
        ) else {
            throw keyError?.takeRetainedValue() ?? APIError.invalidResponse
        }
        var encryptionError: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(
            key,
            .rsaEncryptionPKCS1,
            Data(value.utf8) as CFData,
            &encryptionError
        ) as Data? else {
            throw encryptionError?.takeRetainedValue() ?? APIError.invalidResponse
        }
        return encrypted.base64EncodedString()
    }
}

private enum ASN1 {
    static func integer(_ value: Data) -> Data {
        var bytes = value
        while bytes.count > 1 && bytes.first == 0 && bytes[1] < 0x80 {
            bytes.removeFirst()
        }
        if let first = bytes.first, first >= 0x80 {
            bytes.insert(0, at: 0)
        }
        return tagged(0x02, value: bytes)
    }

    static func sequence(_ values: [Data]) -> Data {
        tagged(0x30, value: values.reduce(into: Data()) { $0.append($1) })
    }

    private static func tagged(_ tag: UInt8, value: Data) -> Data {
        Data([tag]) + length(value.count) + value
    }

    private static func length(_ count: Int) -> Data {
        if count < 128 {
            return Data([UInt8(count)])
        }
        var value = count
        var bytes: [UInt8] = []
        while value > 0 {
            bytes.insert(UInt8(value & 0xff), at: 0)
            value >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }
}
