import AuthenticationServices
import Foundation
import UIKit

@MainActor
final class WebAuthnService: NSObject {
    static let shared = WebAuthnService()

    private var continuation: CheckedContinuation<ASAuthorization, Error>?

    func register(options: WebAuthnRegistrationPublicKey) async throws -> WebAuthnRegistrationPayload {
        guard let challenge = Data(base64URLEncoded: options.challenge),
              let userID = Data(base64URLEncoded: options.user.id) else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: options.rp.id
        )
        let request = provider.createCredentialRegistrationRequest(
            challenge: challenge,
            name: options.user.name,
            userID: userID
        )
        request.displayName = options.user.displayName ?? options.user.name
        request.userVerificationPreference = .required

        let authorization = try await perform(requests: [request])
        guard let credential = authorization.credential
            as? ASAuthorizationPlatformPublicKeyCredentialRegistration,
              let attestationObject = credential.rawAttestationObject else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }
        let credentialID = credential.credentialID.base64URLEncodedString()
        return WebAuthnRegistrationPayload(
            id: credentialID,
            rawId: credentialID,
            clientDataJSON: credential.rawClientDataJSON.base64URLEncodedString(),
            attestationObject: attestationObject.base64URLEncodedString(),
            transports: ["internal"]
        )
    }

    func authenticate(options: WebAuthnAuthenticationPublicKey) async throws -> WebAuthnAssertionPayload {
        guard let challenge = Data(base64URLEncoded: options.challenge) else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: options.rpId
        )
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        request.userVerificationPreference = .required

        let authorization = try await perform(requests: [request])
        guard let credential = authorization.credential
            as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }
        let credentialID = credential.credentialID.base64URLEncodedString()
        return WebAuthnAssertionPayload(
            id: credentialID,
            rawId: credentialID,
            clientDataJSON: credential.rawClientDataJSON.base64URLEncodedString(),
            authenticatorData: credential.rawAuthenticatorData.base64URLEncodedString(),
            signature: credential.signature.base64URLEncodedString(),
            userHandle: credential.userID.isEmpty
                ? nil
                : credential.userID.base64URLEncodedString()
        )
    }

    private func perform(requests: [ASAuthorizationRequest]) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: requests)
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
}

extension WebAuthnService: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        continuation?.resume(returning: authorization)
        continuation = nil
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

extension WebAuthnService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
