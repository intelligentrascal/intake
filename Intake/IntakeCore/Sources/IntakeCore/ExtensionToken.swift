import Foundation

public enum ExtensionToken: Sendable {
    public enum ParseError: Error, Equatable, CustomStringConvertible, Sendable {
        case empty
        case invalid(String)

        public var description: String {
            switch self {
            case .empty:
                "Enter at least one extension."
            case .invalid(let token):
                "“\(token)” isn’t a valid extension. Use letters and numbers, no dots."
            }
        }
    }

    public static func parse(_ raw: String) -> Result<Set<String>, ParseError> {
        let pieces = raw.split { character in
            character == "," || character == ";" || character.isWhitespace
        }
        let tokens = pieces.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }

        guard !tokens.isEmpty else {
            return .failure(.empty)
        }

        var parsed: Set<String> = []
        for token in tokens {
            var cleaned = token.lowercased()
            if cleaned.hasPrefix(".") {
                cleaned.removeFirst()
            }
            guard cleaned.range(of: "^[a-z0-9]{1,16}$", options: .regularExpression) != nil else {
                return .failure(.invalid(token))
            }
            parsed.insert(cleaned)
        }
        return .success(parsed)
    }

    public static func display(_ extensions: Set<String>) -> String {
        extensions.sorted().joined(separator: ", ")
    }
}

public enum FolderNameToken: Sendable {
    public enum ParseError: Error, Equatable, CustomStringConvertible, Sendable {
        case empty
        case invalid

        public var description: String {
            switch self {
            case .empty:
                "Enter a folder name."
            case .invalid:
                "Folder names can’t be empty or contain slashes or colons."
            }
        }
    }

    public static func parse(_ raw: String) -> Result<String, ParseError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.empty)
        }
        if trimmed == "." || trimmed == ".." {
            return .failure(.invalid)
        }
        if trimmed.contains("/") || trimmed.contains(":") || trimmed.contains("\0") {
            return .failure(.invalid)
        }
        return .success(trimmed)
    }
}
