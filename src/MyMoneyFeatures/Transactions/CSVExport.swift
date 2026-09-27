import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// 交給 ShareLink 的 CSV:使用者選好分享目標時才向後端抓檔，寫成暫存檔再分享(parity 刻意偏離第 18 項)。
public struct CSVExport: Transferable, Sendable {
    public let fileName: String
    public let fetch: @Sendable () async throws -> Data

    public init(fileName: String, fetch: @escaping @Sendable () async throws -> Data) {
        self.fileName = fileName
        self.fetch = fetch
    }

    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            let url = FileManager.default.temporaryDirectory.appending(path: export.fileName)
            try await export.fetch().write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
