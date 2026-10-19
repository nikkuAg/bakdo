import SwiftUI

struct DictionaryView: View {
    @State private var settings = AppSettings.shared
    @State private var newWord = ""
    @State private var newFrom = ""
    @State private var newTo = ""

    var body: some View {
        PageScaffold(title: "Dictionary", subtitle: "Teach Inscribo the names and words you use, and fix anything it keeps getting wrong.") {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Vocabulary",
                                  detail: "Names, product terms and jargon. Inscribo hints these to the model so they're spelled right.")
                    HStack {
                        TextField("Add a word or name, e.g. Priya, Kubernetes, Figma", text: $newWord)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(addWord)
                        Button("Add", action: addWord)
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if settings.vocabulary.isEmpty {
                        Text("No words yet.")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(settings.vocabulary, id: \.self) { word in
                                Chip(text: word) {
                                    withAnimation { settings.vocabulary.removeAll { $0 == word } }
                                }
                            }
                        }
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Replacements & snippets",
                                  detail: "Whenever Inscribo hears the left side, it types the right side. Use it to fix spellings (Versal → Vercel) or expand shortcuts (my email → you@company.com).")
                    HStack(spacing: 8) {
                        TextField("When I say…", text: $newFrom)
                            .textFieldStyle(.roundedBorder)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        TextField("Type this", text: $newTo)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(addReplacement)
                        Button("Add", action: addReplacement)
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(newFrom.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if !settings.replacements.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(settings.replacements) { item in
                                HStack(spacing: 10) {
                                    Text(item.from)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                    Text(item.to)
                                        .foregroundStyle(Theme.accent)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    IconButton(symbol: "trash", help: "Remove") {
                                        withAnimation { settings.replacements.removeAll { $0.id == item.id } }
                                    }
                                }
                                .font(.system(size: 13))
                                .padding(.vertical, 8)
                                Divider()
                            }
                        }
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Voice commands", detail: "Built in. Turn them off in Settings.")
                    CommandRow(say: "new line", does: "Starts a new line")
                    CommandRow(say: "new paragraph", does: "Starts a new paragraph")
                }
            }
        }
    }

    private func addWord() {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, !settings.vocabulary.contains(word) else { newWord = ""; return }
        withAnimation { settings.vocabulary.append(word) }
        newWord = ""
    }

    private func addReplacement() {
        let from = newFrom.trimmingCharacters(in: .whitespaces)
        guard !from.isEmpty else { return }
        withAnimation { settings.replacements.append(Replacement(from: from, to: newTo)) }
        newFrom = ""
        newTo = ""
    }
}

struct SectionHeader: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CommandRow: View {
    let say: String
    let does: String

    var body: some View {
        HStack {
            Text("“\(say)”").font(.system(size: 13, weight: .medium))
            Spacer()
            Text(does).font(.system(size: 12.5)).foregroundStyle(.secondary)
        }
    }
}

private struct Chip: View {
    let text: String
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Text(text).font(.system(size: 12.5, weight: .medium))
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .opacity(hovering ? 1 : 0.45)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(Theme.accentSoft))
        .foregroundStyle(Theme.accent)
        .onHover { hovering = $0 }
    }
}

/// Wrapping horizontal layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
