#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import NaturalSuggestCore

private struct LexiconDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .tabSeparatedText, .plainText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
public struct PersonalLexiconView: View {
    @ObservedObject var model: SuggestionModel
    @State private var query = ""
    @State private var importing = false
    @State private var exporting = false
    @State private var preview = false
    @State private var pending: [PersonalLexiconEntry] = []
    @State private var message = ""
    @State private var document = LexiconDocument(data: Data())
    @State private var exportType = UTType.json
    @State private var exportName = "NaturalKana-SNS.json"
    public init(model: SuggestionModel) { self.model = model }
    private var matches: [PersonalLexiconEntry] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.personalEntries.filter { term.isEmpty || [$0.term, $0.reading, $0.meaning].contains(where: { $0.localizedCaseInsensitiveContains(term) }) }
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SNS 词库 · 释义与表达参考").font(.title2.bold())
            Text("在这里查词无需联网。生成建议时，仅将当前句子命中的词语、释义和用法发送给已配置的服务商，不发送整本词库。词条不会自动成为假名转换候选；常用姓名等请放在“词典”页。")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("导入词表…") { importing = true }
                Button("导出词库…") {
                    do {
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        document = LexiconDocument(data: try encoder.encode(model.personalEntries))
                        exportType = .json; exportName = "NaturalKana-SNS.json"; exporting = true
                    } catch { message = "导出失败。" }
                }.disabled(model.personalEntries.isEmpty)
                Button("保存 TSV 模板…") {
                    document = LexiconDocument(data: Data(PersonalLexicon.template.utf8))
                    exportType = .tabSeparatedText; exportName = "SNS词表模板.tsv"; exporting = true
                }
                Spacer()
                Text("\(model.personalEntries.count) / 2000 条").foregroundStyle(.secondary)
            }
            Text("支持 UTF-8 的 TSV / JSON，最大 1 MB。必填：词语、释义；可选：读音、例句、用法、来源。PDF 和照片请先提取、校对成词表。同名词条会在确认导入后更新。")
                .font(.caption).foregroundStyle(.secondary)
            TextField("搜索词语、读音或中文释义", text: $query)
            if !message.isEmpty { Text(message).font(.callout).textSelection(.enabled) }
            if model.personalEntries.isEmpty {
                Spacer()
                Text("尚未导入词条").font(.headline).frame(maxWidth: .infinity)
                Text("先保存模板，用表格软件填写，再导出为 UTF-8 制表符分隔文本。这里只显示你导入的内容，不把未核实的种子词条当成书中内容。")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(matches) { entry in
                    row(entry).contextMenu {
                        Button("删除此词条", role: .destructive) {
                            do { try model.removePersonalEntry(entry.id); message = "已删除“\(entry.term)”。" }
                            catch { message = "删除失败。" }
                        }
                    }
                }
            }
        }.padding(18).onAppear { model.reload() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .tabSeparatedText, .plainText]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 1_000_001) <= 1_000_000 else {
                    throw PersonalLexiconError.invalid("文件超过 1 MB；请拆分词表。")
                }
                pending = try PersonalLexicon.parse(Data(contentsOf: url), json: url.pathExtension.lowercased() == "json")
                preview = true
            } catch let error as PersonalLexiconError { message = error.localizedDescription }
            catch { message = "无法读取文件；请选择 UTF-8 的 TSV 或 JSON 词表。" }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: exportType, defaultFilename: exportName) { result in
            switch result { case .success: message = "文件已保存。"; case .failure: message = "文件未保存。" }
        }
        .sheet(isPresented: $preview) {
            VStack(alignment: .leading, spacing: 12) {
                Text("预览导入：\(pending.count) 条").font(.title2.bold())
                Text("确认后合并到本机词库，同名词条更新。内容来自你提供的文件，不代表已核实或仍在流行。")
                List(Array(pending.prefix(100))) { row($0) }
                if pending.count > 100 { Text("此处预览前 100 条，将导入全部 \(pending.count) 条。") }
                HStack {
                    Button("取消") { pending = []; preview = false }
                    Spacer()
                    Button("确认导入") {
                        do {
                            try model.importPersonalLexicon(pending)
                            message = "已合并 \(pending.count) 条，词库现有 \(model.personalEntries.count) 条；立即生效。"
                            pending = []; preview = false
                        } catch { message = error.localizedDescription; preview = false }
                    }.buttonStyle(.borderedProminent)
                }
            }.padding(20).frame(width: 570, height: 500)
        }
    }
    private func row(_ entry: PersonalLexiconEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.term + (entry.reading.isEmpty ? "" : "（\(entry.reading)）")).font(.headline)
            Text(entry.meaning)
            if !entry.example.isEmpty { Text("例句：" + entry.example) }
            if !entry.note.isEmpty { Text("用法：" + entry.note).foregroundStyle(.secondary) }
            if !entry.source.isEmpty { Text("来源：" + entry.source).font(.caption).foregroundStyle(.secondary) }
        }.textSelection(.enabled).padding(.vertical, 4)
    }
}
#endif
