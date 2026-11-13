import SwiftData
import SwiftUI

/// Sorting the lines that wait for an answer, one at a time: a big card, a
/// grid of colorful groups, one touch each. The answer is remembered for the
/// same place, so every touch may sort several lines.
struct ReviewFlow: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<LedgerEntry> { !$0.removed }, sort: \LedgerEntry.date, order: .reverse)
    private var entries: [LedgerEntry]

    /// How many lines waited when the flow opened.
    @State private var startCount: Int?
    /// Lines left for another time, in this sitting only.
    @State private var skipped: Set<String> = []
    /// The group that was just chosen, while its color fills the screen.
    @State private var flash: SpendCategory?
    @State private var refining: LedgerEntry?
    /// After this many the flow stops to ask whether to go on.
    @State private var pauseAt = ReviewFlow.sitting

    private static let sitting = 12
    private static let stone = Artwork(0x57534E, 0x292524)

    private var waitingAll: [LedgerEntry] {
        Ledger.effective(entries).filter { $0.needsAnswer }
    }

    private var groups: [SpendCategory] {
        SpendCategory.all.filter { $0.id != SpendCategory.incomeID }
    }

    var body: some View {
        let all: [LedgerEntry] = waitingAll
        let waiting: [LedgerEntry] = all.filter { !skipped.contains($0.id) }
        let started: Int = startCount ?? all.count
        let done: Int = max(started - all.count, 0)
        let current: LedgerEntry? = waiting.first
        let isPaused: Bool = current != nil && done >= pauseAt
        ZStack {
            AmbientGround(artwork: Theme.blue)
            VStack(spacing: 0) {
                topBar(left: waiting.count, done: done, started: started)
                if let current, !isPaused {
                    ScrollView {
                        VStack(spacing: 16) {
                            card(current, alike: alike(current, in: all))
                                .id(current.id)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .offset(y: 18)),
                                    removal: .opacity))
                            Text("מה זה היה?")
                                .font(.system(size: 20, weight: .heavy))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                                      spacing: 10) {
                                ForEach(groups) { group in
                                    tile(group)
                                }
                            }
                            HStack(spacing: 10) {
                                smallButton("בחירה מדויקת יותר", symbol: "list.bullet") {
                                    refining = current
                                }
                                smallButton("לא עכשיו", symbol: "arrow.uturn.forward") {
                                    Feedback.tap()
                                    withAnimation(.smooth(duration: 0.3)) { _ = skipped.insert(current.id) }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                        .animation(.smooth(duration: 0.3), value: current.id)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                } else {
                    closing(done: done, left: all.count, isPaused: isPaused)
                }
            }
            if let flash {
                ReviewFlood(group: flash)
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .arrives()
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear {
            if startCount == nil { startCount = waitingAll.count }
        }
        .sheet(item: $refining) { entry in
            CategoryPicker(entry: entry)
        }
    }

    // MARK: Parts

    private func topBar(left: Int, done: Int, started: Int) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("בירור מהיר")
                        .font(.system(size: 28, weight: .heavy))
                    Text(left == 0 ? "אין תנועות שמחכות" : (left == 1 ? "נשארה תנועה אחת" : "נשארו \(left) תנועות"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Color.primary)
                        .frame(width: 40, height: 40)
                        .background(Theme.chip, in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("סגירה")
            }
            if started > 0 {
                GeometryReader { proxy in
                    let share: CGFloat = CGFloat(min(max(Double(done) / Double(started), 0), 1))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.chip)
                        Capsule().fill(Theme.blue.gradient)
                            .frame(width: max(proxy.size.width * share, share > 0 ? 8 : 0))
                    }
                }
                .frame(height: 8)
                .animation(.smooth(duration: 0.4), value: done)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    /// Other waiting lines from the same place, which one answer sorts too.
    private func alike(_ entry: LedgerEntry, in all: [LedgerEntry]) -> Int {
        let key: String = Ledger.merchantKey(entry.title)
        return all.filter { $0.id != entry.id && Ledger.merchantKey($0.title) == key }.count
    }

    /// The line in question, large.
    private func card(_ entry: LedgerEntry, alike: Int) -> some View {
        let day: String = entry.date.formatted(Date.FormatStyle(locale: Ledger.hebrew).weekday(.wide).day().month(.wide))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(entry.source)
                    .font(.system(size: 13, weight: .heavy))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(.white.opacity(0.2), in: Capsule())
                if entry.pending {
                    Text("עוד לא סופי")
                        .font(.system(size: 13, weight: .heavy))
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(.white.opacity(0.2), in: Capsule())
                }
                Spacer()
                Text(day)
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(0.9)
            }
            Text(entry.title)
                .font(.system(size: 28, weight: .heavy))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.top, 8)
            BigMoney(value: (-entry.amount).double, size: 52, duration: 0.5)
            if let payments = entry.paymentsText {
                Text(payments)
                    .font(.system(size: 14, weight: .semibold))
                    .opacity(0.92)
            }
            if let memo = entry.memo, !memo.isEmpty {
                Text(memo)
                    .font(.system(size: 14, weight: .medium))
                    .opacity(0.9)
                    .lineLimit(2)
            }
            if alike > 0 {
                Label(alike == 1 ? "עוד תנועה אחת מאותו מקום תסודר יחד איתה"
                      : "עוד \(alike) תנועות מאותו מקום יסודרו יחד איתה",
                      systemImage: "square.stack.3d.up.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(0.92)
                    .padding(.top, 2)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .livingCard(ReviewFlow.stone, radius: 28, seed: 0.2, watermark: "questionmark")
        .accessibilityElement(children: .combine)
    }

    private func tile(_ group: SpendCategory) -> some View {
        Button {
            answer(group)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: group.symbol)
                    .font(.system(size: 21, weight: .bold))
                    .frame(height: 26)
                Text(group.title)
                    .font(.system(size: 12, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 82)
            .background(group.artwork.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.pressable)
    }

    private func smallButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .heavy))
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Theme.chip, in: Capsule())
        }
        .buttonStyle(.pressable)
    }

    /// The end of the sitting, or a pause in the middle of a long one.
    private func closing(done: Int, left: Int, isPaused: Bool) -> some View {
        let title: String = isPaused ? "\(done) תנועות סודרו"
            : (done == 0 ? (left == 0 ? "אין מה לברר" : "נשאר לפעם אחרת") : "הכול מסודר")
        var text: String = ""
        if isPaused {
            text = "אפשר להמשיך עכשיו, ואפשר לעצור כאן. מה שסודר כבר נכנס למספרים של החודש."
        } else if done == 0 {
            text = left == 0 ? "כל התנועות כבר במקומן." : (left == 1 ? "תנועה אחת מחכה לפעם הבאה." : "\(left) תנועות מחכות לפעם הבאה.")
        } else {
            text = (done == 1 ? "תנועה אחת קיבלה מקום." : "\(done) תנועות קיבלו מקום.")
                + " האפליקציה תזכור את התשובות לפעם הבאה."
            if left > 0 { text += left == 1 ? " נשארה אחת לפעם אחרת." : " נשארו \(left) לפעם אחרת." }
        }
        let shown: String = text
        return VStack(spacing: 14) {
            Spacer()
            Image(systemName: isPaused ? "pause.circle.fill" : "checkmark.seal.fill")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 140, height: 140)
                .background(Theme.emerald.gradient, in: Circle())
                .shadow(color: Theme.emerald.end.opacity(0.4), radius: 22, y: 12)
            Text(title)
                .font(.system(size: 30, weight: .heavy))
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            Text(shown)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
            Spacer()
            if isPaused {
                Button {
                    Feedback.tap()
                    withAnimation(.smooth(duration: 0.3)) { pauseAt += ReviewFlow.sitting }
                } label: {
                    Text("להמשיך")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Theme.blue.gradient, in: Capsule())
                }
                .buttonStyle(.pressable)
            }
            Button {
                dismiss()
            } label: {
                Text(isPaused ? "מספיק להיום" : "סיום")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(isPaused ? Color.primary : Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(isPaused ? AnyShapeStyle(Theme.chip) : AnyShapeStyle(Theme.emerald.gradient), in: Capsule())
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .onAppear {
            if done > 0, !isPaused { Feedback.celebrate() }
        }
    }

    // MARK: Answering

    private func answer(_ group: SpendCategory) {
        guard flash == nil, let entry = waitingAll.first(where: { !skipped.contains($0.id) }) else { return }
        Feedback.done()
        withAnimation(.smooth(duration: 0.2)) { flash = group }
        Task { @MainActor in
            // The color holds for a moment; the next line is waiting under it.
            try? await Task.sleep(for: .seconds(0.45))
            Ledger.answer(entry, with: group, in: context)
            try? await Task.sleep(for: .seconds(0.1))
            withAnimation(.smooth(duration: 0.3)) { flash = nil }
        }
    }
}

/// The chosen group's color over the whole screen, for a moment.
private struct ReviewFlood: View {
    let group: SpendCategory
    @State private var isIn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            group.artwork.gradient
                .ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: group.symbol)
                    .font(.system(size: 58, weight: .bold))
                    .frame(width: 128, height: 128)
                    .background(.white.opacity(0.2), in: Circle())
                Text(group.title)
                    .font(.system(size: 26, weight: .heavy))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .padding(24)
            .scaleEffect(isIn || reduceMotion ? 1 : 0.72)
            .opacity(isIn ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.32, bounce: 0.22)) { isIn = true }
        }
        .accessibilityHidden(true)
    }
}
