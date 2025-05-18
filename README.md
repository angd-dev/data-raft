# DataRaft

DataRaft is a minimalistic Swift library for safe, predictable, and concurrent SQLite access.

## Overview

DataRaft provides a lightweight, high-level infrastructure for working with SQLite in Swift. It ensures thread-safe database access, streamlined transaction management, and a flexible migration system—without abstracting away SQL or imposing an ORM.

Built on top of [DataLiteCore](https://github.com/angd-dev/data-lite-core) (a lightweight Swift SQLite wrapper) and [DataLiteCoder](https://github.com/angd-dev/data-lite-coder) (for type-safe encoding and decoding), DataRaft is designed for real-world applications where control, safety, and reliability are essential.

The core philosophy behind DataRaft is to let developers retain full access to SQL while providing a simple and robust foundation for building database-powered applications.

## Requirements

- **Swift**: 6.0 or later
- **Platforms**: macOS 10.14+, iOS 12.0+, Linux

## Installation

To add DataRaft to your project, use Swift Package Manager (SPM).

> **Important:** The API of `DataRaft` is currently unstable and may change without notice. It is **strongly recommended** to pin the dependency to a specific commit to ensure compatibility and avoid unexpected breakage when the API evolves.

### Adding to an Xcode Project

1. Open your project in Xcode.
2. Navigate to the `File` menu and select `Add Package Dependencies`.
3. Enter the repository URL: `https://github.com/angd-dev/data-raft.git`
4. Choose the version to install.
5. Add the library to your target module.

### Adding to Package.swift

If you are using Swift Package Manager with a `Package.swift` file, add the dependency like this:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YourProject",
    dependencies: [
        .package(url: "https://github.com/angd-dev/data-raft.git", branch: "develop")
    ],
    targets: [
        .target(
            name: "YourTarget",
            dependencies: [
                .product(name: "DataRaft", package: "data-raft")
            ]
        )
    ]
)
```

## Additional Resources

For more information and usage examples, see the [documentation](https://docs.angd.dev/?package=data-raft&version=develop). You can also explore related projects like [DataLiteCore](https://github.com/angd-dev/data-lite-core) and [DataLiteCoder](https://github.com/angd-dev/data-lite-coder).

## License

This project is licensed under the MIT License. See the `LICENSE` file for details.
