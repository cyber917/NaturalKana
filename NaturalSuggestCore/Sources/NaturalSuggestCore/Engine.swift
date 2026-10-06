import Foundation

public struct LRUCache<Key: Hashable, Value> {
    private var values: [Key: Value] = [:]
    private var order: [Key] = []
    private let capacity: Int
    public init(capacity: Int = 64) { self.capacity = max(1, capacity) }
    public mutating func get(_ key: Key) -> Value? {
        guard let value = values[key] else { return nil }
        order.removeAll { $0 == key }; order.append(key); return value
    }
    public mutating func put(_ key: Key, _ value: Value) {
        values[key] = value; order.removeAll { $0 == key }; order.append(key)
        while order.count > capacity { values.removeValue(forKey: order.removeFirst()) }
    }
    public mutating func clear() { values.removeAll(); order.removeAll() }
}
@MainActor public final class DailyBudget {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func reserve(_ requests: Int, limit: Int, now: Date = Date()) -> Bool {
        let day = Int(Calendar.current.startOfDay(for: now).timeIntervalSince1970)
        if defaults.integer(forKey: "nk.budget.day") != day {
            defaults.set(day, forKey: "nk.budget.day"); defaults.set(0, forKey: "nk.budget.used")
        }
        let used = defaults.integer(forKey: "nk.budget.used")
        guard limit <= 0 || used + requests <= limit else { return false }
        defaults.set(used + requests, forKey: "nk.budget.used"); return true
    }
}
@MainActor public final class SuggestionEngine {
    public private(set) var suggestions: [Suggestion] = []
    public private(set) var status: Diagnostics = .idle
    public private(set) var requestSeconds: Double?
    public private(set) var cacheHit = false
    public private(set) var receivedCandidateCount: Int?
    private var personalEntries: [PersonalLexiconEntry] = []
    public var onChange: (([Suggestion], Diagnostics) -> Void)?
    private var task: Task<Void, Never>?
    private var generation = 0
    private var current: DraftSnapshot?
    private var currentSettings: String?
    private var acceptedSnapshot: DraftSnapshot?
    private var dismissedSnapshot: DraftSnapshot?
    private var lastRequest = ContinuousClock.now - .seconds(10)
    private var cache = LRUCache<String, ResponseValidator.Report>()
    private let profile: any LanguageProfile
    private let budget: DailyBudget
    private let prompt: PromptBuilder
    private let lexicon: Lexicon
    public init(profile: any LanguageProfile = JapaneseDraftProfile(), budget: DailyBudget = DailyBudget(),
                prompt: PromptBuilder, lexicon: Lexicon = .bundled()) {
        self.profile = profile; self.budget = budget; self.prompt = prompt; self.lexicon = lexicon
    }
    public func cancel(clearCache: Bool = false) {
        requestSeconds = nil; cacheHit = false; receivedCandidateCount = nil
        generation += 1; task?.cancel(); task = nil; current = nil; currentSettings = nil; acceptedSnapshot = nil
        if clearCache { cache.clear(); dismissedSnapshot = nil }; publish([], .idle)
    }
    public func dismiss() {
        dismissedSnapshot = current ?? dismissedSnapshot
        cancel()
    }
    public func setPersonalLexicon(_ entries: [PersonalLexiconEntry]) {
        guard entries != personalEntries else { return }
        personalEntries = entries; cancel(clearCache: true)
    }
    private func publish(_ items: [Suggestion], _ state: Diagnostics) { suggestions = items; status = state; onChange?(items, state) }
    public func update(_ snapshot: DraftSnapshot, settings: SuggestionSettings, provider: any SuggestionProvider, explicit: Bool = false) {
        // A late host update must not reopen a palette dismissed for this draft.
        // Editing the draft, changing fields, or an explicit request resumes suggestions.
        if dismissedSnapshot == snapshot, !explicit { return }
        dismissedSnapshot = nil
        // Repeated clicks must not cancel a valid in-flight response. Changed text/settings still cancel it.
        let fingerprint = settings.fingerprint
        if current == snapshot, currentSettings == fingerprint,
           status == .requesting || (!explicit && status != .idle) { return }
        cancel(); current = snapshot; currentSettings = fingerprint
        guard settings.enabled, settings.consent else { publish([], .disabled); return }
        guard !snapshot.secure, !settings.blockedApps.contains(snapshot.appID) else { publish([], .filtered(.protectedField)); return }
        guard !snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { publish([], .filtered(.empty)); return }
        guard !snapshot.composingLatin else { publish([], .filtered(.composing)); return }
        guard snapshot.text.count >= max(1, settings.minimumLength) else { publish([], .filtered(.tooShort(max(1, settings.minimumLength)))); return }
        guard profile.accepts(snapshot.text, composingLatin: false) else { publish([], .filtered(.language)); return }
        let version = generation
        let key = TextNormalization.nfkc(snapshot.text) + fingerprint + prompt.version
        if let cached = cache.get(key) { cacheHit = true; acceptedSnapshot = snapshot; publish(cached.suggestions, cached.diagnostics); return }
        publish([], .waiting)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let punctuation = snapshot.text.last.map { "。！？!?".contains($0) } ?? false
                if !explicit && !punctuation { try await Task.sleep(for: .milliseconds(max(0, settings.debounceMilliseconds))) }
                let earliest = lastRequest + .milliseconds(700)
                if ContinuousClock.now < earliest { try await Task.sleep(until: earliest, clock: .continuous) }
                try Task.checkCancellation()
                guard generation == version else { return }
                guard budget.reserve(settings.qualityMode ? 3 : 1, limit: settings.dailyCap) else { publish([], .quota); return }
                lastRequest = .now; publish([], .requesting)
                let request = try prompt.make(draft: snapshot.text, settings: settings, lexicon: lexicon, personalEntries: personalEntries)
                let started = ContinuousClock.now
                let response = try await provider.suggest(request, quality: settings.qualityMode)
                try Task.checkCancellation()
                guard generation == version, current == snapshot else { return }
                let elapsed = started.duration(to: .now).components
                requestSeconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                let report = try ResponseValidator().inspect(response.json, draft: snapshot.text, settings: settings)
                receivedCandidateCount = report.receivedCount
                let items = report.suggestions
                // Explicitly natural drafts can be reused without another request. Unknown empty results cannot.
                if !items.isEmpty || report.assessment == .natural { cache.put(key, report) }
                acceptedSnapshot = snapshot
                publish(items, report.diagnostics)
            } catch is CancellationError { /* New text must never revive old suggestions. */ }
            catch {
                guard generation == version, !Task.isCancelled else { return }
                publish([], Diagnostics(error: error))
            }
        }
    }
    public var suggestionDraft: String { acceptedSnapshot?.text ?? "" }
    public func accept(index: Int, current snapshot: DraftSnapshot) -> String? {
        guard snapshot == acceptedSnapshot, !snapshot.secure, suggestions.indices.contains(index) else { cancel(); return nil }
        let text = suggestions[index].text; cancel(); return text
    }
}
