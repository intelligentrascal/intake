import Foundation

public enum FileCategory: String, CaseIterable, Identifiable, Sendable, Codable, Hashable {
    case documents
    case spreadsheets
    case presentations
    case images
    case video
    case audio
    case archives
    case installers
    case other

    public var id: String { rawValue }

    public var folderName: String {
        switch self {
        case .documents: "Documents"
        case .spreadsheets: "Spreadsheets"
        case .presentations: "Presentations"
        case .images: "Images"
        case .video: "Video"
        case .audio: "Audio"
        case .archives: "Archives"
        case .installers: "Installers"
        case .other: "Other"
        }
    }

    public var systemImage: String {
        switch self {
        case .documents: "doc.text"
        case .spreadsheets: "tablecells"
        case .presentations: "rectangle.on.rectangle"
        case .images: "photo"
        case .video: "film"
        case .audio: "waveform"
        case .archives: "archivebox"
        case .installers: "arrow.down.app"
        case .other: "questionmark.folder"
        }
    }

    public var defaultExtensions: Set<String> {
        switch self {
        case .documents:
            ["pdf", "doc", "docx", "pages", "txt", "rtf", "odt", "md"]
        case .spreadsheets:
            ["xls", "xlsx", "numbers", "csv", "tsv"]
        case .presentations:
            ["ppt", "pptx", "key", "odp"]
        case .images:
            ["png", "jpg", "jpeg", "heic", "webp", "gif", "svg", "tiff"]
        case .video:
            ["mp4", "mov", "m4v", "mkv", "webm"]
        case .audio:
            ["mp3", "m4a", "wav", "aiff", "flac"]
        case .archives:
            ["zip", "7z", "rar", "tar", "gz"]
        case .installers:
            ["dmg", "pkg"]
        case .other:
            []
        }
    }
}
