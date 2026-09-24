// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Understudy",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.55.0"),
    ],
    targets: [
        .executableTarget(
            name: "Understudy",
            dependencies: [.product(name: "Supabase", package: "supabase-swift")],
            path: "Sources/Understudy"
        ),
    ]
)
