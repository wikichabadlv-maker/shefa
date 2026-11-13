import Foundation
import SwiftData

/// One line from the bank or a credit card, plus what we know about it.
@Model
final class LedgerEntry {
    @Attribute(.unique) var id: String
    var date: Date
    var title: String
    var amount: Decimal
    var source: String
    var method: String?
    /// `nil` means the app does not know yet what this purchase was.
    var categoryID: String?
    var note: String?
    var isSample: Bool
    var subID: String? = nil
    var subTitle: String? = nil
    /// Set when the family marks this line as fixed, variable or one-time
    /// differently from what its sub-category normally is.
    var natureOverride: String? = nil
    var updatedAt: Date = Date.now
    /// A line the family added by hand and later deleted.
    var removed: Bool = false
    /// For a card purchase: the day the card company takes the money from
    /// the bank account.
    var chargeDate: Date? = nil
    /// Which payment this line is, and out of how many, for a purchase split
    /// into payments. Both are 0 for an ordinary purchase.
    var installment: Int = 0
    var installments: Int = 0
    /// Not final at the bank or the card company yet; the amount may change.
    var pending: Bool = false
    /// What the bank wrote next to the line, if anything.
    var memo: String? = nil
    /// The last four digits of the account or the card.
    var account: String? = nil

    init(id: String, date: Date, title: String, amount: Decimal, source: String,
         method: String? = nil, categoryID: String? = nil, note: String? = nil,
         isSample: Bool = false, sub: SubCategory? = nil) {
        self.id = id
        self.date = date
        self.title = title
        self.amount = amount
        self.source = source
        self.method = method
        self.categoryID = categoryID
        self.note = note
        self.isSample = isSample
        self.subID = sub?.id
        self.subTitle = sub?.title
    }

    var category: SpendCategory? { SpendCategory.find(categoryID) }

    static let manualPrefix = "manual-"

    /// Added by hand in the app, for example a cash purchase.
    var isManual: Bool { id.hasPrefix(LedgerEntry.manualPrefix) }

    /// An expense that still waits for the user to say what it was.
    var needsAnswer: Bool { categoryID == nil && amount < 0 }

    var nature: Nature {
        Nature(rawValue: natureOverride ?? "") ?? SubCategory.find(subID)?.nature ?? .variable
    }

    var detail: String {
        var parts = [subTitle ?? category?.title ?? (amount < 0 ? "לבירור" : "הכנסה")]
        parts.append(source)
        if let method, method != source { parts.append(method) }
        if let payments = paymentsText { parts.append(payments) }
        return parts.joined(separator: " · ")
    }

    /// True for a purchase that is paid in several monthly payments.
    var isInPayments: Bool { installments > 1 && installment > 0 }

    /// For example "תשלום 3 מתוך 10".
    var paymentsText: String? {
        isInPayments ? "תשלום \(installment) מתוך \(installments)" : nil
    }

    /// What is still to be paid after this payment.
    var paymentsLeft: Decimal {
        guard isInPayments, installment < installments else { return 0 }
        return -amount * Decimal(installments - installment)
    }
}

/// What the user taught the app: purchases at this merchant go to this category.
@Model
final class MerchantRule {
    @Attribute(.unique) var merchant: String
    var categoryID: String
    var subID: String? = nil
    var subTitle: String? = nil

    init(merchant: String, categoryID: String, subID: String? = nil, subTitle: String? = nil) {
        self.merchant = merchant
        self.categoryID = categoryID
        self.subID = subID
        self.subTitle = subTitle
    }
}

/// A sub-category the family added themselves.
@Model
final class CustomSub {
    @Attribute(.unique) var id: String
    var groupID: String
    var title: String
    var createdAt: Date

    init(groupID: String, title: String) {
        self.id = "custom.\(UUID().uuidString)"
        self.groupID = groupID
        self.title = title
        self.createdAt = .now
    }
}
