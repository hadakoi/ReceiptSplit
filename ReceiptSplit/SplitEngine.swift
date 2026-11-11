import Foundation

struct PersonBalance: Identifiable {
    let id: UUID
    let name: String
    let owed: Int
    let paid: Int
    var balance: Int { paid - owed }
}
struct Transfer: Identifiable {
    var id: String { from + "→" + to }
    let from: String
    let to: String
    let amount: Int
}
struct SplitResult {
    var balances: [PersonBalance] = []
    var issues: [String] = []
    var transfers: [Transfer] = []
}
enum SplitEngine {
    // Largest-remainder allocation conserves every paise, including negative adjustments.
    static func distribute(_ amount: Int, weights: [Int]) -> [Int] {
        guard !weights.isEmpty, weights.allSatisfy({ $0 >= 0 }), weights.reduce(0, +) > 0 else { return Array(repeating: 0, count: weights.count) }
        let sum = weights.reduce(0, +)
        let magnitude = abs(amount)
        // Decimal intermediates avoid overflowing when a large bill has large weights.
        let numerators = weights.map { Decimal(magnitude) * Decimal($0) }
        var shares = numerators.map { numerator -> Int in
            var quotient = numerator / Decimal(sum), rounded = Decimal()
            NSDecimalRound(&rounded, &quotient, 0, .down)
            return NSDecimalNumber(decimal: rounded).intValue
        }
        let remainders = numerators.indices.map { numerators[$0] - Decimal(shares[$0]) * Decimal(sum) }
        let order = weights.indices.sorted {
            let a = remainders[$0], b = remainders[$1]
            return a == b ? $0 < $1 : a > b
        }
        let remainder = magnitude - shares.reduce(0, +)
        for index in order.prefix(remainder) { shares[index] += 1 }
        return amount < 0 ? shares.map { -$0 } : shares
    }
    static func calculate(_ receipt: Receipt) -> SplitResult {
        let people = receipt.people.sorted { $0.id.uuidString < $1.id.uuidString }
        var result = SplitResult()
        guard !people.isEmpty else { result.issues = ["Add at least one participant."]; return result }
        if receipt.items.isEmpty { result.issues.append("Add at least one item.") }
        if receipt.total < 0 || receipt.discount > receipt.subtotal { result.issues.append("Discounts and adjustments cannot make the bill negative.") }
        var owed = Array(repeating: 0, count: people.count)
        for item in receipt.items {
            if item.needsReview { result.issues.append("Review the scanned item ‘\(item.name)’.") }
            let values = people.map { item.allocations[$0.id.uuidString] ?? 0 }
            let shares: [Int]
            switch item.splitMode {
            case "equal":
                // Empty allocation means everyone; explicit allocations mean selected people only.
                let weights = item.allocations.isEmpty ? people.map { _ in 1 } : values.map { $0 > 0 ? 1 : 0 }
                guard weights.reduce(0, +) > 0 else { result.issues.append("Assign ‘\(item.name)’ to someone."); continue }
                shares = distribute(item.total, weights: weights)
            case "custom":
                guard values.allSatisfy({ $0 >= 0 }), values.reduce(0, +) == item.total else { result.issues.append("Custom amounts for ‘\(item.name)’ must equal \(Money.format(item.total))."); continue }
                shares = values
            case "quantity", "weighted":
                guard values.allSatisfy({ $0 >= 0 }), values.reduce(0, +) > 0 else { result.issues.append("Set shares for ‘\(item.name)’."); continue }
                if item.splitMode == "quantity" && values.reduce(0, +) != item.quantity { result.issues.append("Assigned quantities for ‘\(item.name)’ must total \(item.quantity)."); continue }
                shares = distribute(item.total, weights: values)
            default: result.issues.append("Choose a split method for ‘\(item.name)’."); continue
            }
            for i in owed.indices { owed[i] += shares[i] }
        }
        let extras = distribute(receipt.adjustments, weights: owed.reduce(0, +) > 0 ? owed : people.map { _ in 1 })
        for i in owed.indices { owed[i] += extras[i] }
        result.balances = people.indices.map { PersonBalance(id: people[$0].id, name: people[$0].name, owed: owed[$0], paid: people[$0].paid) }
        if result.balances.contains(where: { $0.owed < 0 }) { result.issues.append("Adjustments cannot create a negative share.") }
        if receipt.people.reduce(0, { $0 + $1.paid }) != receipt.total { result.issues.append("Payments must equal the bill total before settling.") }
        if !receipt.isReconciled { result.issues.append(receipt.printedTotal == nil ? "Enter the printed total to reconcile the receipt." : "The calculated total differs from the printed total.") }
        guard result.issues.isEmpty else { return result }
        var debtors = result.balances.filter { $0.balance < 0 }.map { ($0.name, -$0.balance) }
        var creditors = result.balances.filter { $0.balance > 0 }.map { ($0.name, $0.balance) }
        var d = 0, c = 0
        while d < debtors.count && c < creditors.count {
            let amount = min(debtors[d].1, creditors[c].1)
            result.transfers.append(Transfer(from: debtors[d].0, to: creditors[c].0, amount: amount))
            debtors[d].1 -= amount; creditors[c].1 -= amount
            if debtors[d].1 == 0 { d += 1 }; if creditors[c].1 == 0 { c += 1 }
        }
        return result
    }
    static func summary(_ receipt: Receipt) -> String {
        let result = calculate(receipt)
        var lines = ["ReceiptSplit · \(receipt.merchant)", receipt.date.formatted(date: .abbreviated, time: .omitted), ""]
        lines += receipt.items.map { "\($0.name) ×\($0.quantity): \(Money.format($0.total))" }
        lines += ["", "Subtotal: \(Money.format(receipt.subtotal))", "CGST: \(Money.format(receipt.cgst))", "SGST: \(Money.format(receipt.sgst))", "Service: \(Money.format(receipt.service))", "Tip: \(Money.format(receipt.tip))", "Discount: \(Money.format(receipt.discount))", "Rounding: \(Money.format(receipt.rounding))", "Total: \(Money.format(receipt.total))", ""]
        lines += result.balances.map { "\($0.name): owes \(Money.format($0.owed)), paid \(Money.format($0.paid))" }
        lines += result.transfers.map { "\($0.from) → \($0.to): \(Money.format($0.amount))" }
        return lines.joined(separator: "\n")
    }
}
