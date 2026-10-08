// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// Generated file. Do not edit.
//

import PackageDescription

let package = Package(
    name: "FlutterGeneratedPluginSwiftPackage",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "FlutterGeneratedPluginSwiftPackage", type: .static, targets: ["FlutterGeneratedPluginSwiftPackage"])
    ],
    dependencies: [
        .package(name: "firebase_core", path: "../.packages/firebase_core-4.12.1"),
        .package(name: "cloud_firestore", path: "../.packages/cloud_firestore-6.7.1"),
        .package(name: "google_sign_in_ios", path: "../.packages/google_sign_in_ios-6.3.6"),
        .package(name: "google_mobile_ads", path: "../.packages/google_mobile_ads-9.1.0"),
        .package(name: "webview_flutter_wkwebview", path: "../.packages/webview_flutter_wkwebview-3.26.2"),
        .package(name: "firebase_auth", path: "../.packages/firebase_auth-6.5.6"),
        .package(name: "FlutterFramework", path: "../.packages/FlutterFramework")
    ],
    targets: [
        .target(
            name: "FlutterGeneratedPluginSwiftPackage",
            dependencies: [
                .product(name: "firebase-core", package: "firebase_core"),
                .product(name: "cloud-firestore", package: "cloud_firestore"),
                .product(name: "google-sign-in-ios", package: "google_sign_in_ios"),
                .product(name: "google-mobile-ads", package: "google_mobile_ads"),
                .product(name: "webview-flutter-wkwebview", package: "webview_flutter_wkwebview"),
                .product(name: "firebase-auth", package: "firebase_auth"),
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
