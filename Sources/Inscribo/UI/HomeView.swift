import SwiftUI

struct HomeView: View {
    @Binding var page: Page
    @State private var history = HistoryStore.shared
    @State private var settings = AppSettings.shared
    @State private var search = ""

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    var body: some View {
        PageScaffold(title: greeting, subtitle: "Speak, and it shall be inscribed — in English, Hindi or Hinglish, wherever your cursor is.") {
            HStack(spacing: 6) {
                Text("Hold").foregroundStyle(.secondary)
                KeyCap(text: settings.triggerKey.shortLabel)
                Text("to talk ·").foregroundStyle(.secondary)
                Text("double-tap").foregroundStyle(.secondary)
                KeyCap(text: settings.triggerKey.shortLabel)
                Text("for hands-free ·").foregroundStyle(.secondary)
                KeyCap(text: "esc")
                Text("to cancel").foregroundStyle(.secondary)
            }
            .font(.system(size: 12.5))
            .padding(.top, -10)

            if settings.fixShortcutEnabled {
                HStack(spacing: 6) {
                    Text("Select any text and press").foregroundStyle(.secondary)
                    KeyCap(text: settings.fixShortcut.display)
                    Text("to cast Reparo and fix its grammar and typos.").foregroundStyle(.secondary)
                }
                .font(.system(size: 12.5))
                .padding(.top, -16)
            }

            StatsRow(history: history)

            TryItCard()

            HStack {
                Text("History")
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                Spacer()
                if !history.items.isEmpty {
                    TextField("Search", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }
            }
            .padding(.top, 6)

            if history.items.isEmpty {
                EmptyHistory()
            } else {
                HistoryList(items: filtered)
            }
        }
    }

    private var filtered: [Transcript] {
        guard !search.isEmpty else { return history.items }
        return history.items.filter { $0.text.localizedCaseInsensitiveContains(search) }
    }
}

private struct StatsRow: View {
    let history: HistoryStore

    var body: some View {
        HStack(spacing: 12) {
            StatTile(value: "\(history.streakDays)", unit: history.streakDays == 1 ? "day" : "days",
                     label: "Streak", symbol: "flame.fill", tint: Theme.warm)
            StatTile(value: history.totalWords.formatted(), unit: "words",
                     label: "Dictated", symbol: "text.word.spacing", tint: Theme.accent)
            StatTile(value: history.wordsPerMinute > 0 ? "\(history.wordsPerMinute)" : "—", unit: "wpm",
                     label: "Speaking speed", symbol: "speedometer", tint: .teal)
            StatTile(value: "\(history.minutesSaved)", unit: "min",
                     label: "Time saved", symbol: "clock.fill", tint: .green)
        }
    }
}

private struct StatTile: View {
    let value: String
    let unit: String
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(tint.opacity(0.13)))
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                    Text(unit)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Text(label)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A scratch field to try dictation without leaving the app.
private struct TryItCard: View {
    @State private var text = ""
    @State private var settings = AppSettings.shared
    @State private var controller = DictationController.shared
    @FocusState private var focused: Bool

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Practice the charm", systemImage: "wand.and.stars")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    if controller.phase == .recording && controller.committed {
                        Label("Listening…", systemImage: "waveform")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .symbolEffect(.variableColor.iterative, isActive: true)
                    } else if controller.phase == .transcribing {
                        Text("Writing…").font(.system(size: 12)).foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 4) {
                            Text("or hold")
                            KeyCap(text: "space")
                        }
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !text.isEmpty {
                        Button("Clear") { text = "" }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Hold Space (or \(settings.triggerKey.shortLabel) anywhere) and say something like “Kal ki meeting 4 baje shift kar do, and send the deck to everyone.”")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 1)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .scrollContentBackground(.hidden)
                        .focused($focused)
                }
                .font(.system(size: 14))
                .frame(height: 64)
            }
        }
        .holdSpaceToDictate(focus: $focused)
    }
}

private struct EmptyHistory: View {
    var body: some View {
        Card {
            VStack(spacing: 10) {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.goldGradient)
                Text("Your inscriptions will appear here")
                    .font(.system(size: 14, weight: .medium))
                Text("Everything stays on this Mac. Nothing is sent to the cloud.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }
}

private struct HistoryList: View {
    let items: [Transcript]

    private var groups: [(day: Date, items: [Transcript])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: items.prefix(400)) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!) }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(groups, id: \.day) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(dayLabel(group.day))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                HistoryRow(item: item)
                                if index < group.items.count - 1 {
                                    Divider().padding(.leading, 86)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month().day())
    }
}

private struct HistoryRow: View {
    let item: Transcript
    @State private var hovering = false
    @State private var copied = false
    @State private var editing = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(item.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                    .font(.system(size: 13.5))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    if let app = item.appName { Text(app) }
                    Text("·")
                    Text("\(item.wordCount) words")
                    Text("·")
                    Text(String(format: "%.1fs", item.processingSeconds))
                }
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            }
            HStack(spacing: 4) {
                IconButton(symbol: "pencil", help: "Fix this transcript") { editing = true }
                    .popover(isPresented: $editing, arrowEdge: .bottom) { EditTranscript(item: item, isPresented: $editing) }
                IconButton(symbol: copied ? "checkmark" : "doc.on.doc", help: "Copy") {
                    TextInserter.copyToClipboard(item.text)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                }
                IconButton(symbol: "trash", help: "Delete") {
                    withAnimation { HistoryStore.shared.delete(item) }
                }
            }
            .opacity(hovering || copied || editing ? 1 : 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(hovering ? Color.primary.opacity(0.03) : .clear)
        .onHover { hovering = $0 }
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .medium))
                .frame(width: 26, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Correct a transcript. Inscribo compares the fix with what it heard and offers to remember
/// recurring mistakes as Dictionary replacements.
private struct EditTranscript: View {
    let item: Transcript
    @Binding var isPresented: Bool
    @State private var text = ""
    @State private var suggestions: [(heard: String, meant: String)] = []
    @State private var saved = false
    @State private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(saved ? "Saved — remember these fixes?" : "Fix what Inscribo got wrong")
                .font(.system(size: 13, weight: .semibold))
            if !saved {
                TextEditor(text: $text)
                    .font(.system(size: 13.5))
                    .frame(width: 380, height: 90)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                if item.trainingID != nil {
                    Label("This recording will learn the corrected text", systemImage: "person.wave.2")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Cancel") { isPresented = false }.buttonStyle(SecondaryButtonStyle())
                    Button("Save") { save() }.buttonStyle(PrimaryButtonStyle())
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { _, pair in
                    HStack(spacing: 8) {
                        Text(pair.heard).strikethrough().foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                        Text(pair.meant).fontWeight(.medium)
                        Spacer()
                        if settings.replacements.contains(where: { $0.from == pair.heard && $0.to == pair.meant }) {
                            Label("Added", systemImage: "checkmark").font(.system(size: 11.5)).foregroundStyle(.green)
                        } else {
                            Button("Always fix") { settings.replacements.append(Replacement(from: pair.heard, to: pair.meant)) }
                                .buttonStyle(.plain).foregroundStyle(Theme.accent)
                        }
                    }
                    .font(.system(size: 13))
                }
                HStack {
                    Spacer()
                    Button("Done") { isPresented = false }.buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .padding(16)
        .frame(width: 412)
        .onAppear { text = item.text }
    }

    private func save() {
        let fixed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        HistoryStore.shared.update(item, text: fixed)
        suggestions = WordAlignment.mistakes(meant: fixed, heard: item.text).map { pair in
            (pair.heard, Self.originalCasing(of: pair.meant, in: fixed))
        }
        if suggestions.isEmpty { isPresented = false } else { saved = true }
    }

    /// Recovers the user's capitalisation ("vercel" → "Vercel") from the corrected text.
    private static func originalCasing(of phrase: String, in text: String) -> String {
        if let range = text.range(of: phrase, options: .caseInsensitive) { return String(text[range]) }
        return phrase
    }
}
