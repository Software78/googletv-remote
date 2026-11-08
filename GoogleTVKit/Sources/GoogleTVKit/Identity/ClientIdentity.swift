import Foundation
import Crypto
import _CryptoExtras
import X509
import SwiftASN1

/// RSA public key numbers as minimal big-endian unsigned bytes.
public struct RSAPublicNumbers: Equatable, Sendable {
    public let modulus: Data
    public let exponent: Data

    /// Extract from a DER X.509 certificate (ours or the TV's).
    public init(certificateDER: Data) throws {
        let cert: Certificate
        do { cert = try Certificate(derEncoded: [UInt8](certificateDER)) }
        catch { throw TVError.protocolViolation("Unparseable certificate") }
        guard let rsa = _RSA.Signing.PublicKey(cert.publicKey) else {
            throw TVError.protocolViolation("Certificate key is not RSA")
        }
        try self.init(pkcs1DER: rsa.pkcs1DERRepresentation)
    }

    init(pkcs1DER: Data) throws {
        do {
            let node = try DER.parse([UInt8](pkcs1DER))
            let (n, e): (ArraySlice<UInt8>, ArraySlice<UInt8>) = try DER.sequence(node, identifier: .sequence) { nodes in
                let n = try ArraySlice<UInt8>(derEncoded: &nodes)
                let e = try ArraySlice<UInt8>(derEncoded: &nodes)
                return (n, e)
            }
            self.modulus = PairingSecret.strip(Data(n))
            self.exponent = PairingSecret.strip(Data(e))
        } catch {
            throw TVError.protocolViolation("Unparseable RSA public key")
        }
    }
}

/// The long-lived client certificate + private key the TV pairs against.
public struct ClientIdentity: Sendable, Equatable {
    public let certificateDER: Data
    /// PKCS#1 RSAPrivateKey DER.
    public let privateKeyDER: Data
    public let publicNumbers: RSAPublicNumbers

    public init(certificateDER: Data, privateKeyDER: Data) throws {
        self.certificateDER = certificateDER
        self.privateKeyDER = privateKeyDER
        self.publicNumbers = try RSAPublicNumbers(certificateDER: certificateDER)
    }
}

public enum CertificateFactory {
    /// Generates a self-signed RSA-2048 certificate, mirroring androidtvremote2's generator
    /// (CN = hostname, CA:true pathlen 0, SAN DNS, 10-year validity, SHA-256).
    public static func generate(commonName: String = "atvremote") throws -> ClientIdentity {
        do {
            let rsaKey = try _RSA.Signing.PrivateKey(keySize: .bits2048)
            let key = Certificate.PrivateKey(rsaKey)
            let name = try DistinguishedName { CommonName(commonName) }
            let now = Date()
            let extensions = try Certificate.Extensions {
                Critical(BasicConstraints.isCertificateAuthority(maxPathLength: 0))
                SubjectAlternativeNames([.dnsName(commonName)])
            }
            var serial = [UInt8](repeating: 0, count: 16)
            for i in serial.indices { serial[i] = UInt8.random(in: 0...255) }
            serial[0] &= 0x7F
            let cert = try Certificate(
                version: .v3,
                serialNumber: Certificate.SerialNumber(bytes: serial),
                publicKey: key.publicKey,
                notValidBefore: now.addingTimeInterval(-3600),
                notValidAfter: now.addingTimeInterval(10 * 365 * 24 * 3600),
                issuer: name, subject: name,
                signatureAlgorithm: .sha256WithRSAEncryption,
                extensions: extensions,
                issuerPrivateKey: key)
            var serializer = DER.Serializer()
            try serializer.serialize(cert)
            return try ClientIdentity(
                certificateDER: Data(serializer.serializedBytes),
                privateKeyDER: rsaKey.derRepresentation)
        } catch let e as TVError {
            throw e
        } catch {
            throw TVError.certificateGeneration(String(describing: error))
        }
    }
}
