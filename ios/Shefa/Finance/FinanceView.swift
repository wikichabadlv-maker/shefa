import SwiftUI

enum FinanceSection: String, CaseIterable, Identifiable {
    case overview = "סקירה"
    case transactions = "תנועות"
    case budget = "תקציב"
    case savings = "חיסכון"

    var id: String { rawValue }
}

struct FinanceView: View {
    @State private var section: FinanceSection = .transactions

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("מדור", selection: $section) {
                        ForEach(FinanceSection.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch section {
                    case .overview:
                        MonthHeroCard(month: SampleData.month)
                    case .transactions:
                        TransactionsList(days: SampleData.days)
                    case .budget:
                        ContentUnavailableView("תקציב", systemImage: "chart.pie.fill",
                                               description: Text("תקציב לפי קטגוריות נבנה בשלב הבא."))
                    case .savings:
                        SavingsList(month: SampleData.month, goals: SampleData.goals)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.ground)
            .navigationTitle("פיננסים")
        }
    }
}

struct TransactionsList: View {
    let days: [TransactionDay]

    var body: some View {
        ForEach(days) { day in
            VStack(spacing: 6) {
                HStack {
                    Text(day.title)
                    Spacer()
                    Text(Money.text(day.total, fractionDigits: 2, showPlus: true))
                        .monospacedDigit()
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)

                VStack(spacing: 0) {
                    ForEach(Array(day.items.enumerated()), id: \.element.id) { index, item in
                        TransactionRow(transaction: item)
                        if index < day.items.count - 1 {
                            Divider().padding(.leading, 54)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .cardSurface()
            }
        }
    }
}

struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 12) {
            ArtworkIcon(artwork: transaction.artwork, symbol: transaction.symbol)
            VStack(alignment: .leading, spacing: 1) {
                Text(transaction.title)
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
                Text(transaction.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(transaction.needsAnswer ? Theme.amberInk : .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Money.text(transaction.amount, fractionDigits: 2, showPlus: true))
                .font(.system(size: 16, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(transaction.amount > 0 ? Theme.accent : .primary)
        }
        .frame(height: 60)
        .accessibilityElement(children: .combine)
    }
}

struct SavingsList: View {
    let month: MonthSummary
    let goals: [SavingsGoal]

    var body: some View {
        MaaserCard(month: month)

        SectionHeader(title: "יעדי חיסכון")

        VStack(spacing: 0) {
            ForEach(Array(goals.enumerated()), id: \.element.id) { index, goal in
                HStack(spacing: 12) {
                    ArtworkIcon(artwork: goal.artwork, symbol: goal.symbol)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(goal.title).font(.system(size: 16, weight: .bold))
                            Spacer()
                            Text(goal.share, format: .percent.precision(.fractionLength(0)))
                                .font(.system(size: 14, weight: .bold))
                                .monospacedDigit()
                        }
                        ProgressView(value: goal.share).tint(goal.artwork.start)
                        Text("\(Money.text(goal.saved)) מתוך \(Money.text(goal.target))")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 12)
                if index < goals.count - 1 {
                    Divider().padding(.leading, 54)
                }
            }
        }
        .padding(.horizontal, 14)
        .cardSurface()
    }
}

/// The gold card that tracks maaser for the month.
struct MaaserCard: View {
    let month: MonthSummary
    @State private var isChomesh = false

    private var due: Decimal { isChomesh ? month.maaserDue * 2 : month.maaserDue }
    private var remaining: Decimal { max(due - month.maaserGiven, 0) }
    private var share: Double {
        guard due > 0 else { return 0 }
        return min(NSDecimalNumber(decimal: month.maaserGiven / due).doubleValue, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("נותר לתת החודש")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Picker("שיעור", selection: $isChomesh) {
                    Text("מעשר 10%").tag(false)
                    Text("חומש 20%").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
            }
            Text(Money.text(remaining))
                .font(.system(size: 50, weight: .heavy))
                .monospacedDigit()
                .contentTransition(.numericText())
            ProgressView(value: share).tint(.white)
            HStack {
                Text("ניתן \(Money.text(month.maaserGiven))")
                Spacer()
                Text("חובה \(Money.text(due))")
            }
            .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(Theme.amber.gradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color(hex: 0xB45309).opacity(0.45), radius: 20, y: 12)
        .animation(.snappy, value: isChomesh)
    }
}
