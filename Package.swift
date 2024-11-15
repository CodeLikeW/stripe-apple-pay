// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "StripeApplePay",
    defaultLocalization: "en",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "StripeApplePay",
            targets: ["StripeApplePay"]),
    ],
    dependencies: [
        .package(url: "https://github.com/CodeLikeW/stripe-core", from: "24.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "StripeApplePay",
            dependencies: [.product(name: "StripeCore", package: "stripe-core")]
        ),
        .testTarget(
            name: "StripeApplePayTests",
            dependencies: ["StripeApplePay"]
        ),
    ]
)
