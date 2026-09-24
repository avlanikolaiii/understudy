// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Understudy",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.55.0"),
    ],
    targets: [
        // Pure Swift: models, the report engine, and later the run engine. No UI and no network,
        // so qa/run.py compiles and checks it on its own.
        .target(name: "UnderstudyCore", path: "Sources/UnderstudyCore"),
        .executableTarget(
            name: "Understudy",
            dependencies: ["UnderstudyCore", .product(name: "Supabase", package: "supabase-swift")],
            path: "Sources/Understudy"
        ),
    ]
)
