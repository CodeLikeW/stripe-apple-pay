
import Foundation
import PassKit
import StripeCore

public struct STPApplePaySimple {

    private func isValid(clientSecret: String) -> Bool {
        guard clientSecret != STPApplePayContext.COMPLETE_WITHOUT_CONFIRMING_INTENT else {
            return false
        }
        return true
    }

    /// - Returns: true for Setup Intent, false for Payment Intent
    private func isForSetupIntent(clientSecret: String) -> Bool {
        StripeAPI.SetupIntentConfirmParams.isClientSecretValid(clientSecret)
    }

    public func complete(
        payment: PKPayment,
        returnURLPath: String?,
        usingClientSecretProvider clientSecretProvider: @escaping () async -> Result<String, Error>,
        withAPI stripe: StripeAsyncAPI = StripeAsyncAPI()
    ) async -> PKPaymentAuthorizationResult {
        do {
            // 1. Create PaymentMethod
            let paymentMethod = try await stripe.paymentMethod(for: payment)
            // 2. Get the client secret via callback
            let result = await clientSecretProvider()
            switch result {
            case .success(let clientSecret):
                guard isValid(clientSecret: clientSecret) else {
                    throw StripeAsyncError.invalidClientSecret
                }
                // 3. Handle (Payment or Setup) Intent
                if isForSetupIntent(clientSecret: clientSecret) {
                    // SetupIntent
                    let setupIntent = try await stripe.setupIntentFor(clientSecret: clientSecret)
                    try await stripe.complete(setupIntent: setupIntent,
                                              paymentMethod: paymentMethod,
                                              clientSecret: clientSecret,
                                              returnURLPath: returnURLPath)
                    return .init(status: .success, errors: nil) // success
                } else {
                    // PaymentIntent
                    let paymentIntent = try await stripe.paymentIntentFor(clientSecret: clientSecret)
                    try await stripe.complete(paymentIntent: paymentIntent, paymentMethod: paymentMethod, payment: payment, clientSecret: clientSecret)
                    return .init(status: .success, errors: nil) // success
                }
            case .failure(let error):
                throw error
            }
        } catch (let error) {
            return .init(status: .failure, errors: [error])
        }
    }
}
