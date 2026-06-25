import Foundation

// MARK: - Codex 会话日志扫描器

/// 扫描 `~/.codex/sessions/**/*.jsonl`，逐行解析出 token_count 事件。
///
/// 设计要点：
/// - 只关心 `type=="event_msg"` 且 `payload.type=="token_count"` 的行，其余行跳过。
/// - 单行解析失败不影响整体扫描（容错：跳过坏行而非中断）。
/// - 支持全量扫描与增量扫描（按文件 mtime 过滤）。
public struct CodexLogScanner: Sendable {
    /// Codex 会话日志根目录，默认 `~/.codex/sessions`。
    public let sessionsDirectory: URL

    public init(sessionsDirectory: URL? = nil) {
        if let url = sessionsDirectory {
            self.sessionsDirectory = url
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.sessionsDirectory = home.appendingPathComponent(".codex/sessions")
        }
    }

    /// 扫描所有 jsonl 文件，返回解析出的全部 token_count 事件（按时间升序）。
    public func scanAllEvents() -> [TokenCountEvent] {
        let files = enumerateJSONLFiles()
        var events: [TokenCountEvent] = []
        events.reserveCapacity(files.count * 8)  // 粗略预估
        for file in files {
            events.append(contentsOf: parseEvents(in: file))
        }
        events.sort { $0.timestamp < $1.timestamp }
        return events
    }

    /// 增量扫描：只解析 mtime 晚于 `since` 的文件。
    public func scanEventsModifiedSince(_ since: Date) -> [TokenCountEvent] {
        let fm = FileManager.default
        let files = enumerateJSONLFiles().filter { url in
            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let mtime = attrs[.modificationDate] as? Date else {
                return true  // 拿不到 mtime 就当作需要扫描
            }
            return mtime > since
        }
        var events: [TokenCountEvent] = []
        for file in files {
            events.append(contentsOf: parseEvents(in: file))
        }
        events.sort { $0.timestamp < $1.timestamp }
        return events
    }

    /// 列出 sessions 目录下所有 .jsonl 文件（递归）。
    public func enumerateJSONLFiles() -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sessionsDirectory.path) else { return [] }

        var results: [URL] = []
        let enumerator = fm.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        guard let enumerator else { return [] }

        for case let url as URL in enumerator {
            if url.pathExtension == "jsonl" {
                results.append(url)
            }
        }
        return results
    }

    /// 解析单个 jsonl 文件中的所有 token_count 事件。
    /// 逐行解析：坏行/非 token_count 行直接跳过，不中断。
    public func parseEvents(in file: URL) -> [TokenCountEvent] {
        guard let data = try? Data(contentsOf: file),
              data.isEmpty == false else {
            return []
        }
        guard let fullText = String(data: data, encoding: .utf8) else { return [] }

        var events: [TokenCountEvent] = []
        let decoder = JSONDecoder()
        for line in fullText.split(separator: "\n", omittingEmptySubsequences: true) {
            // 快速预筛：行内不含 token_count 直接跳过，避免无谓的 JSON 解析
            guard line.contains("\"token_count\"") else { continue }
            guard let lineData = line.data(using: .utf8) else { continue }
            // 解析整行；非 token_count 的行会在 init 里被抛错，这里吞掉
            if let event = try? decoder.decode(TokenCountEvent.self, from: lineData) {
                events.append(event)
            }
        }
        return events
    }
}
