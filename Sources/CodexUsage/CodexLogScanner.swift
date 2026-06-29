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

    /// 单个日志文件已经扫描到的位置。
    public struct FileState: Sendable, Equatable {
        public let path: String
        public let size: UInt64
        public let modificationDate: Date
    }

    /// 一次扫描的结果，同时带回文件状态，供后续增量扫描使用。
    public struct ScanResult: Sendable, Equatable {
        public let events: [TokenCountEvent]
        public let fileStates: [FileState]
    }

    /// 增量扫描结果。`requiresFullRescan` 为 true 时，调用方应回退到全量扫描。
    public struct IncrementalScanResult: Sendable, Equatable {
        public let events: [TokenCountEvent]
        public let fileStates: [FileState]
        public let requiresFullRescan: Bool
    }

    /// 扫描所有 jsonl 文件，返回解析出的全部 token_count 事件（按时间升序）。
    public func scanAllEvents() -> [TokenCountEvent] {
        scanAllEventsWithState().events
    }

    /// 全量扫描所有 jsonl 文件，并记录每个文件的已读位置。
    public func scanAllEventsWithState() -> ScanResult {
        let fileInfos = enumerateJSONLFileInfos()
        var events: [TokenCountEvent] = []
        events.reserveCapacity(fileInfos.count * 8)  // 粗略预估
        var states: [FileState] = []
        states.reserveCapacity(fileInfos.count)

        for fileInfo in fileInfos {
            events.append(contentsOf: parseEvents(in: fileInfo.url))
            states.append(fileInfo.state)
        }
        events.sort { $0.timestamp < $1.timestamp }
        return ScanResult(events: events, fileStates: states)
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

    /// 真正的增量扫描：只读取新增文件或已有文件追加的字节。
    public func scanIncrementalEvents(since previousStates: [FileState]) -> IncrementalScanResult {
        let fileInfos = enumerateJSONLFileInfos()
        let previousByPath = Dictionary(uniqueKeysWithValues: previousStates.map { ($0.path, $0) })
        let currentPaths = Set(fileInfos.map(\.state.path))
        let previousPaths = Set(previousByPath.keys)

        guard previousPaths.isSubset(of: currentPaths) else {
            return IncrementalScanResult(events: [], fileStates: [], requiresFullRescan: true)
        }

        var events: [TokenCountEvent] = []
        var nextStates: [FileState] = []
        nextStates.reserveCapacity(fileInfos.count)

        for fileInfo in fileInfos {
            let state = fileInfo.state
            nextStates.append(state)

            guard let previous = previousByPath[state.path] else {
                events.append(contentsOf: parseEvents(in: fileInfo.url))
                continue
            }

            guard state.size >= previous.size else {
                return IncrementalScanResult(events: [], fileStates: [], requiresFullRescan: true)
            }

            if state.size > previous.size {
                events.append(contentsOf: parseEvents(in: fileInfo.url, fromOffset: previous.size))
            }
        }

        events.sort { $0.timestamp < $1.timestamp }
        return IncrementalScanResult(events: events, fileStates: nextStates, requiresFullRescan: false)
    }

    /// 列出 sessions 目录下所有 .jsonl 文件（递归）。
    public func enumerateJSONLFiles() -> [URL] {
        enumerateJSONLFileInfos().map(\.url)
    }

    private func enumerateJSONLFileInfos() -> [(url: URL, state: FileState)] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sessionsDirectory.path) else { return [] }

        var results: [(url: URL, state: FileState)] = []
        let enumerator = fm.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        guard let enumerator else { return [] }

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
                continue
            }
            let state = FileState(
                path: url.path,
                size: UInt64(values.fileSize ?? 0),
                modificationDate: values.contentModificationDate ?? .distantPast
            )
            results.append((url: url, state: state))
        }
        return results
    }

    /// 解析单个 jsonl 文件中的所有 token_count 事件。
    /// 逐行解析：坏行/非 token_count 行直接跳过，不中断。
    public func parseEvents(in file: URL) -> [TokenCountEvent] {
        parseEvents(in: file, fromOffset: 0)
    }

    /// 从指定字节偏移开始解析。Codex jsonl 是追加写入，因此后台刷新只需读取文件尾部。
    public func parseEvents(in file: URL, fromOffset offset: UInt64) -> [TokenCountEvent] {
        let data: Data?
        if offset == 0 {
            data = try? Data(contentsOf: file)
        } else {
            guard let handle = try? FileHandle(forReadingFrom: file) else { return [] }
            defer { try? handle.close() }
            do {
                try handle.seek(toOffset: offset)
                data = try handle.readToEnd()
            } catch {
                return []
            }
        }

        guard let data,
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
