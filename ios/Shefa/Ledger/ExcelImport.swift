import Foundation
import SwiftData

/// Brings in the family's 2026 budget spreadsheet: one line per category per
/// month, as the family recorded it. These lines are the record for the months
/// they cover; bank lines from the same months are shown but not counted again.
enum ExcelImport {
    static let source = "אקסל"

    private struct File: Decodable {
        let year: Int
        let lines: [Line]
    }

    private struct Line: Decodable {
        let id: String
        let month: Int
        let title: String
        let amount: Double
        let category: String
        let sub: String?
        let subTitle: String?
    }

    static func importIfNeeded(in context: ModelContext) {
        guard let url = Bundle.main.url(forResource: "excel2026", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else { return }

        let existing = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        let ids = Set(existing.map(\.id))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jerusalem") ?? .current

        var added = false
        for line in file.lines where !ids.contains(line.id) {
            let parts = DateComponents(year: file.year, month: line.month, day: 15, hour: 12)
            guard let date = calendar.date(from: parts) else { continue }
            let sub = SubCategory.find(line.sub)
            let entry = LedgerEntry(
                id: line.id, date: date, title: line.title,
                amount: Decimal(string: String(format: "%.2f", line.amount)) ?? 0,
                source: source, categoryID: line.category, sub: sub)
            if sub == nil { entry.subTitle = line.subTitle }
            context.insert(entry)
            added = true
        }
        guard added else { return }
        for entry in existing where entry.isSample {
            context.delete(entry)
        }
        try? context.save()
    }
}

extension Ledger {
    /// The lines that count toward totals. For months the spreadsheet covers,
    /// only its lines count, so nothing is counted twice.
    static func effective(_ entries: [LedgerEntry]) -> [LedgerEntry] {
        let dates = entries.filter { $0.source == ExcelImport.source }.map(\.date)
        guard let last = dates.max(),
              let covered = Calendar.current.dateInterval(of: .month, for: last)
        else { return entries }
        return entries.filter { $0.source == ExcelImport.source || $0.date >= covered.end }
    }
}
