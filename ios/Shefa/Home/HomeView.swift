import SwiftData
import SwiftUI

struct HomeView: View {
    @Binding var selection: AppTab
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]

    private var month: MonthSummary { Ledger.summary(entries) }
    private var question: LedgerEntry? { entries.first { $0.needsAnswer } }
    private var recent: [LedgerEntry] { Array(entries.prefix(3)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(Self.dateLine)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 4)
                        .padding(.bottom, -14)

                    MonthHeroCard(month: month)

                    if let question {
                        QuestionCard(entry: question)
                            .id(question.id)
                            .transition(.opacity)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "יעדי חיסכון") { selection = .finance }
                        ScrollView(.horizontal) {
                            HStack(spacing: 12) {
                                ForEach(SampleData.goals) { goal in
                                    GoalTile(goal: goal)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .scrollIndicators(.hidden)
                        .padding(.horizontal, -16)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "תנועות אחרונות") { selection = .finance }
                        VStack(spacing: 0) {
                            ForEach(recent) { item in
                                TransactionRow(entry: item)
                                if item.id != recent.last?.id {
                                    Divider().padding(.leading, 54)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .cardSurface()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.ground)
            .navigationTitle("בית")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("פקודה מהירה", systemImage: "bolt.fill") {}
                }
            }
        }
    }

    /// For example "יום חמישי · ב׳ בכסלו".
    private static var dateLine: String {
        let weekday = Date.now.formatted(
            Date.FormatStyle(locale: Locale(identifier: "he_IL")).weekday(.wide))
        let hebrew = DateFormatter()
        hebrew.calendar = Calendar(identifier: .hebrew)
        hebrew.locale = Locale(identifier: "he_IL@numbers=hebr")
        hebrew.dateFormat = "d בMMMM"
        return "\(weekday) · \(hebrew.string(from: .now))"
    }
}

/// The vivid emerald card with what is left to spend this month.
struct MonthHeroCard: View {
    let month: MonthSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("נשאר להוציא החודש")
                .font(.system(size: 15, weight: .semibold))
                .opacity(0.9)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("₪")
                    .font(.system(size: 28, weight: .bold))
                Text(Money.digits(month.remaining))
                    .font(.system(size: 56, weight: .heavy))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .environment(\.layoutDirection, .leftToRight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Money.digits(month.remaining)) שקלים")

            ProgressView(value: month.spentShare)
                .tint(.white)
                .padding(.top, 2)

            Text("מתוך \(Money.text(month.budget)) · עוד \(month.daysLeft) ימים")
                .font(.system(size: 13, weight: .medium))
                .opacity(0.9)
                .padding(.top, 2)

            HStack(spacing: 0) {
                stat("הכנסות", Money.text(month.income))
                Divider().overlay(.white.opacity(0.3)).frame(height: 28)
                stat("נחסך", Money.text(month.saved))
                Divider().overlay(.white.opacity(0.3)).frame(height: 28)
                stat("מעשר", Money.text(month.maaserGiven), color: Color(hex: 0xFDE68A))
            }
            .padding(.vertical, 10)
            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.top, 12)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: 0x047857), Color(hex: 0x065F46), Color(hex: 0x0F766E)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(Color(hex: 0x34D399).opacity(0.55))
                    .frame(width: 200, height: 200)
                    .blur(radius: 50)
                    .offset(x: 120, y: -90)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color(hex: 0x047857).opacity(0.45), radius: 22, y: 14)
    }

    private func stat(_ title: String, _ value: String, color: Color = .white) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .opacity(0.85)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A purchase the app could not classify on its own and asks about.
struct QuestionCard: View {
    let entry: LedgerEntry
    @Environment(\.modelContext) private var context
    @State private var isChoosing = false

    private let suggestions = ["food", "home", "gift"].compactMap { SpendCategory.find($0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ArtworkIcon(artwork: Theme.amber, symbol: "questionmark")
                VStack(alignment: .leading, spacing: 1) {
                    Text("מה קנינו ב\(entry.title)?")
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(2)
                    Text("\(entry.date.formatted(Date.FormatStyle(locale: Ledger.hebrew).day().month(.wide))) · \(entry.source) · \(Money.text(entry.amount, fractionDigits: 2))")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                ForEach(suggestions) { category in
                    chip(category.title) {
                        withAnimation(.snappy) { Ledger.answer(entry, with: category, in: context) }
                    }
                }
                chip("אחר…") { isChoosing = true }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .sheet(isPresented: $isChoosing) {
            CategoryPicker(entry: entry)
        }
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Theme.amberGround, in: Capsule())
                .foregroundStyle(Theme.amberInk)
        }
        .buttonStyle(.plain)
    }
}

/// A colorful tile for one savings goal.
struct GoalTile: View {
    let goal: SavingsGoal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: goal.symbol)
                .font(.system(size: 20, weight: .semibold))
            Spacer(minLength: 0)
            Text(goal.title)
                .font(.system(size: 16, weight: .heavy))
                .lineLimit(2)
            ProgressView(value: goal.share)
                .tint(.white)
            Text("\(Money.text(goal.saved)) מתוך \(Money.text(goal.target))")
                .font(.system(size: 12, weight: .medium))
                .opacity(0.9)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(width: 164, height: 150, alignment: .leading)
        .background(goal.artwork.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
