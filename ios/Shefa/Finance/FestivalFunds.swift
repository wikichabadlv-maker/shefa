import SwiftUI

/// The times of the year that cost more than an ordinary month, in the order
/// they come. Each can have a fund of its own, so that a little goes aside
/// every month and the season stops being a surprise.
struct OccasionFunds: View {
    let goals: [SavingsGoal]
    let entries: [LedgerEntry]
    /// Opens a fund that already exists.
    let open: (SavingsGoal) -> Void
    /// Starts a new fund from a prepared draft.
    let start: (GoalDraft) -> Void

    private struct Coming: Identifiable {
        let occasion: Occasion
        let date: Date
        var id: String { occasion.id }
    }

    private var coming: [Coming] {
        var result: [Coming] = []
        for occasion in Occasion.all {
            if let date = occasion.next() { result.append(Coming(occasion: occasion, date: date)) }
        }
        return result.sorted { $0.date < $1.date }
    }

    /// For example "בעוד שבועיים" or "בעוד 5 חודשים".
    static func countdown(to date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        let days: Int = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                                to: calendar.startOfDay(for: date)).day ?? 0
        if days <= 0 { return "היום" }
        if days == 1 { return "מחר" }
        if days < 14 { return "בעוד \(days) ימים" }
        if days < 60 {
            let weeks: Int = Int((Double(days) / 7).rounded())
            return weeks == 2 ? "בעוד שבועיים" : "בעוד \(weeks) שבועות"
        }
        let months: Int = Int((Double(days) / 30.4).rounded())
        return months == 2 ? "בעוד חודשיים" : "בעוד \(months) חודשים"
    }

    private func draft(for occasion: Occasion) -> GoalDraft {
        let target: Decimal? = occasion.suggestedTarget(entries)
        var draft = GoalDraft(title: occasion.fund,
                              targetText: target.map { Money.digits($0).replacingOccurrences(of: ",", with: "") } ?? "",
                              symbol: occasion.symbol, palette: occasion.palette)
        draft.occasion = occasion.id
        if let ready = occasion.deadline() {
            draft.hasDeadline = true
            draft.deadline = ready
        }
        return draft
    }

    var body: some View {
        let list: [Coming] = coming
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("שנה שלמה")
                    .font(.system(size: 22, weight: .heavy))
                Text("המועדים שעולים יותר מחודש רגיל. קצת בכל חודש, והם מפסיקים להפתיע.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(list) { item in
                        let fund: SavingsGoal? = goals.first { $0.occasion == item.occasion.id }
                        Button {
                            Feedback.tap()
                            if let fund {
                                open(fund)
                            } else {
                                start(draft(for: item.occasion))
                            }
                        } label: {
                            tile(item, fund: fund)
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .padding(.horizontal, -16)
        }
    }

    private func tile(_ item: Coming, fund: SavingsGoal?) -> some View {
        let occasion: Occasion = item.occasion
        let artwork: Artwork = SavingsGoal.palettes[abs(occasion.palette) % SavingsGoal.palettes.count]
        // The civil date leads; the Hebrew one follows it for the festivals.
        let day: String = occasion.isCivil ? Ledger.dayText(item.date)
            : Ledger.dayText(item.date) + " · " + HebrewDate.text(item.date)
        let hint: Decimal? = fund == nil ? occasion.suggestedTarget(entries) : nil
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: occasion.symbol)
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.22), in: Circle())
                Spacer(minLength: 4)
                Text(OccasionFunds.countdown(to: item.date))
                    .font(.system(size: 12, weight: .heavy))
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(.white.opacity(0.2), in: Capsule())
            }
            Spacer(minLength: 8)
            Text(occasion.title)
                .font(.system(size: 17, weight: .heavy))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.leading)
            Text(day)
                .font(.system(size: 12, weight: .semibold))
                .opacity(0.88)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let fund {
                GrowBar(share: fund.share, height: 5, track: .white.opacity(0.25), delay: 0.3, fill: Color.white)
                    .padding(.top, 4)
                Text("\(Money.text(fund.saved)) מתוך \(Money.text(fund.target))")
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .heavy))
                    Text(hint.map { "קופה · אשתקד \(Money.text($0))" } ?? "פתיחת קופה")
                        .font(.system(size: 12, weight: .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(.white.opacity(0.22), in: Capsule())
                .padding(.top, 4)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(width: 176, height: 184, alignment: .leading)
        .livingCard(artwork, radius: 24, seed: Double(occasion.palette) * 0.31, watermark: occasion.symbol, isMoving: false)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
