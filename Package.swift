// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SecretSatanBackend",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.9.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.6.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/vapor/jwt.git", from: "5.0.0"),
    ],
    targets: [
        // libgd del sistema: dibuja la imagen de vista previa de cada evento.
        .systemLibrary(
            name: "Cgd",
            pkgConfig: "gdlib",
            providers: [.brew(["gd"]), .apt(["libgd-dev"])]
        ),
        .executableTarget(
            name: "App",
            dependencies: [
                "Cgd",
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "JWT", package: "jwt"),
            ]
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App"),
                .product(name: "XCTVapor", package: "vapor"),
            ]
        ),
    ]
)
