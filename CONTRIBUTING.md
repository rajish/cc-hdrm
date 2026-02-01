# Contributing to cc-hdrm

Thanks for your interest in contributing. This document covers the process for contributing to this project.

## Getting Started

1. Fork the repository
2. Clone your fork
3. Create a branch from `main` for your change

### Development Setup

You need:
- macOS 14.0 (Sonoma) or later
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

```sh
git clone https://github.com/<your-username>/cc-hdrm.git
cd cc-hdrm/cc-hdrm
xcodegen generate
open cc-hdrm.xcodeproj
```

### Running Tests

From Xcode: `Cmd+U`

From the command line:

```sh
cd cc-hdrm/cc-hdrm
xcodegen generate
xcodebuild -project cc-hdrm.xcodeproj -scheme cc-hdrmTests -destination 'platform=macOS' test
```

## How to Contribute

### Reporting Bugs

Open an [issue](https://github.com/rajish/cc-hdrm/issues/new?template=bug_report.md) with:
- macOS version
- Steps to reproduce
- Expected vs actual behavior
- Console logs if relevant (`Console.app`, filter by `cc-hdrm`)

### Suggesting Features

Open an [issue](https://github.com/rajish/cc-hdrm/issues/new?template=feature_request.md) describing:
- The problem you're trying to solve
- Your proposed solution
- Alternatives you've considered

### Submitting Code

1. Open an issue first to discuss the change (unless it's a small fix)
2. Fork and create a branch: `git checkout -b fix/description` or `git checkout -b feat/description`
3. Make your changes
4. Ensure tests pass
5. Submit a pull request against `main`

### Pull Request Guidelines

- Keep PRs focused — one change per PR
- Follow existing code style and naming conventions (see Architecture section below)
- Add tests for new functionality
- Update documentation if behavior changes

## Architecture

The project follows MVVM with these conventions:

| Layer      | Location           | Purpose                            |
| ---------- | ------------------ | ---------------------------------- |
| Models     | `cc-hdrm/Models/`     | Data types, enums, value objects   |
| Services   | `cc-hdrm/Services/`   | API client, Keychain, polling      |
| State      | `cc-hdrm/State/`      | `AppState` — single source of truth  |
| Views      | `cc-hdrm/Views/`      | SwiftUI views                      |
| Extensions | `cc-hdrm/Extensions/` | Type extensions                    |

Key principles:
- Zero external dependencies — use only Apple SDK frameworks
- Protocol-based services for testability
- `@Observable` for state management
- Swift 6.0 strict concurrency

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
