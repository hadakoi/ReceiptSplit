import Foundation
import SwiftData

@Model final class Receipt {
    var id: UUID = UUID()
    var merchant: String = ""
    var date: Date = Date()
    var notes: String = ""
    var cgst: Int = 0
    var sgst: Int = 0
    var service: Int = 0
    var tip: Int = 0
    var discount: Int = 0
    var rounding: Int = 0
    var printedTotal: Int? = nil
    var reviewed: Bool = false
    @Relationship(deleteRule: .cascade) var items: [ReceiptItem] = []
    @Relationship(deleteRule: .cascade) var people: [Participant] = []
    init(merchant: String) { self.merchant = merchant }
    var subtotal: Int { items.reduce(0) { $0 + $1.total } }
    var adjustments: Int { cgst + sgst + service + tip - discount + rounding }
    var total: Int { subtotal + adjustments }
    var difference: Int? { printedTotal.map { total - $0 } }
    var isReconciled: Bool { difference == 0 }
}

@Model final class ReceiptItem {
    var id: UUID = UUID()
    var name: String = ""
    var quantity: Int = 1
    var unitPrice: Int = 0
    var splitMode: String = "equal"
    var allocationData: Data = Data()
    var needsReview: Bool = false
    init(name: String, quantity: Int = 1, unitPrice: Int) {
        self.name = name; self.quantity = quantity; self.unitPrice = unitPrice
    }
    var total: Int { quantity * unitPrice }
    var allocations: [String: Int] {
        get { (try? JSONDecoder().decode([String: Int].self, from: allocationData)) ?? [:] }
        set { allocationData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}

@Model final class Participant {
    var id: UUID = UUID()
    var name: String = ""
    var paid: Int = 0
    init(name: String, paid: Int = 0) { self.name = name; self.paid = paid }
}

enum Money {
    static func parse(_ text: String, signed: Bool = false) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "₹", with: "").replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty, cleaned.range(of: signed ? "^-?[0-9]+(\\.[0-9]{1,2})?$" : "^[0-9]+(\\.[0-9]{1,2})?$", options: .regularExpression) != nil,
              let number = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")),
              abs(number) <= 10_000_000 else { return nil }
        return NSDecimalNumber(decimal: number * 100).intValue
    }
    static func edit(_ cents: Int) -> String { String(format: "%.2f", Double(cents) / 100) }
    static func format(_ cents: Int) -> String {
        (Double(cents) / 100).formatted(.currency(code: "INR"))
    }
}
