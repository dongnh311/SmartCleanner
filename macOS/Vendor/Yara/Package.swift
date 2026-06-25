// swift-tools-version:5.9
import PackageDescription

// Self-contained libyara (4.5.2) vendored as a C target. No OpenSSL / libmagic
// / jansson: the hash module uses macOS CommonCrypto; pe / magic / cuckoo /
// dotnet / dex modules are excluded (Windows/.NET-centric or need extra libs).
let package = Package(
    name: "Yara",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "Yara", targets: ["Yara"]),
    ],
    targets: [
        .target(
            name: "CYara",
            path: "Sources/CYara",
            cSettings: [
                .headerSearchPath("include"),
                .headerSearchPath("."),
                .headerSearchPath("modules"),
                .define("HAVE_COMMONCRYPTO_COMMONCRYPTO_H"),
                .define("USE_MACH_PROC"),
            ]
        ),
        .target(
            name: "Yara",
            dependencies: ["CYara"],
            path: "Sources/Yara"
        ),
    ]
)
