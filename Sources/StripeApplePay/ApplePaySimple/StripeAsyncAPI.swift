
import Foundation
import PassKit
import StripeCore
import os

enum StripeAsyncError: Swift.Error {
    case invalidClientSecret
    case setupIntentConfirmationNotSucceeded
    case setupIntentInvalidState
    case paymentIntentConfirmationNotSucceeded
    case paymentIntentInvalidState
}

public struct StripeAsyncAPI {
    private let apiClient: STPAPIClient

    public init(apiClient: STPAPIClient = STPAPIClient.shared) {
        self.apiClient = apiClient
    }

    // MARK: PaymentMethod
    func paymentMethod(for payment: PKPayment) async throws -> StripeAPI.PaymentMethod {
        try await withCheckedThrowingContinuation { continuation in
            StripeAPI.PaymentMethod.create(
                apiClient: apiClient,
                payment: payment
            ) { result in
                continuation.resume(with: result)
            }
        }
    }

    // MARK: SetupIntent
    func setupIntentFor(clientSecret: String) async throws -> StripeAPI.SetupIntent {
        try await withCheckedThrowingContinuation { continuation in
            StripeAPI.SetupIntent.get(apiClient: apiClient, clientSecret: clientSecret) { result in
                continuation.resume(with: result)
            }
        }
    }

    func complete(
        setupIntent: StripeAPI.SetupIntent,
        paymentMethod: StripeAPI.PaymentMethod,
        clientSecret: String,
        returnURLPath: String?
    ) async throws {
        switch setupIntent.status {
        case .succeeded:
            return // no confirmation is required
        case .requiresConfirmation, .requiresAction, .requiresPaymentMethod:
            var confirmParams = StripeAPI.SetupIntentConfirmParams(
                clientSecret: clientSecret
            )
            confirmParams.paymentMethod = paymentMethod.id
            confirmParams.useStripeSdk = true
            confirmParams.returnUrl = returnURLPath
            try await confirmSetupIntent(params: confirmParams)
        case .canceled, .processing, .unknown, .unparsable, .none:
            throw StripeAsyncError.setupIntentInvalidState
        }
    }

    private func confirmSetupIntent(params: StripeAPI.SetupIntentConfirmParams) async throws {
        try await withCheckedThrowingContinuation { continuation in
            StripeAPI.SetupIntent.confirm(
                apiClient: apiClient,
                params: params
            ) { result in
                switch result {
                case .success(let intent) where intent.status == .succeeded:
                    continuation.resume()
                case .success:
                    continuation.resume(throwing: StripeAsyncError.setupIntentConfirmationNotSucceeded)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: PaymentIntent
    func paymentIntentFor(clientSecret: String) async throws -> StripeAPI.PaymentIntent {
        try await withCheckedThrowingContinuation { continuation in
            StripeAPI.PaymentIntent.get(apiClient: apiClient, clientSecret: clientSecret) { result in
                continuation.resume(with: result)
            }
        }
    }

    func complete(
        paymentIntent: StripeAPI.PaymentIntent,
        paymentMethod: StripeAPI.PaymentMethod,
        payment: PKPayment,
        clientSecret: String
    ) async throws {
        if isConfirmationRequired(for: paymentIntent) {
            var confirmParams = StripeAPI.PaymentIntentParams(
                clientSecret: clientSecret
            )
            confirmParams.paymentMethod = paymentMethod.id
            confirmParams.useStripeSdk = true
            // If a merchant attaches shipping to the PI on their server, the /confirm endpoint will error if we update shipping with a “requires secret key” error message.
            // To accommodate this, don't attach if our shipping is the same as the PI's shipping
            if let paymentShipping = shippingDetails(from: payment),
               paymentIntent.shipping != paymentShipping {
                confirmParams.shipping = paymentShipping
            }
            try await confirmPaymentIntent(params: confirmParams)
            return // success
        } else if paymentIntent.status == .succeeded || paymentIntent.status == .requiresCapture {
            return // success
        } else {
            os_log("The PaymentIntent is in an unexpected state. If you pass confirmation_method = manual when creating the PaymentIntent, also pass confirm = true.  If server-side confirmation fails, double check you are passing the error back to the client.", type: .error)
            throw StripeAsyncError.paymentIntentInvalidState
        }
    }

    private func isConfirmationRequired(for paymentIntent: StripeAPI.PaymentIntent) -> Bool {
        paymentIntent.confirmationMethod == .automatic
            && (paymentIntent.status == .requiresPaymentMethod
                || paymentIntent.status == .requiresConfirmation)
    }

    private func confirmPaymentIntent(params: StripeAPI.PaymentIntentParams) async throws {
        try await withCheckedThrowingContinuation { continuation in
            StripeAPI.PaymentIntent.confirm(
                apiClient: apiClient,
                params: params
            ) { result in
                switch result {
                case .success(let intent) where intent.status == .succeeded
                    || intent.status == .requiresCapture:
                    continuation.resume()
                case .success:
                    continuation.resume(throwing: StripeAsyncError.paymentIntentConfirmationNotSucceeded)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: Shipping Details from PKPayment
    private func shippingDetails(from payment: PKPayment) -> StripeAPI.ShippingDetails? {
        guard let address = payment.shippingContact?.postalAddress,
            let name = payment.shippingContact?.name
        else {
            return nil
        }

        let addressParams = StripeAPI.ShippingDetails.Address(
            city: address.city,
            country: address.isoCountryCode,
            line1: address.street,
            postalCode: address.postalCode,
            state: address.state
        )

        let formatter = PersonNameComponentsFormatter()
        formatter.style = .long
        let shippingParams = StripeAPI.ShippingDetails(
            address: addressParams,
            name: formatter.string(from: name),
            phone: payment.shippingContact?.phoneNumber?.stringValue
        )

        return shippingParams
    }
}
