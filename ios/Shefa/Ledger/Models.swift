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

    /// An expense that still waits for the user to say what it was.
    var needsAnswer: Bool { categoryID == nil && amount < 0 }

    var nature: Nature {
        Nature(rawValue: natureOverride ?? "") ?? SubCategory.find(subID)?.nature ?? .variable
    }

    var detail: String {
        var parts = [subTitle ?? category?.title ?? (amount < 0 ? "לבירור" : "הכנסה")]
        parts.append(source)
        if let method { parts.append(method) }
        return parts.joined(separator: " · ")
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
