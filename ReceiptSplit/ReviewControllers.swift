import UIKit

final class SettlementViewController: StoryboardTableController {
    var receipt: Receipt!
    private var result: SplitResult { SplitEngine.calculate(receipt) }
    override func viewDidLoad() { super.viewDidLoad(); title = "Split & settle"; navigationItem.largeTitleDisplayMode = .never }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); tableView.reloadData() }
    override func numberOfSections(in tableView: UITableView) -> Int { 4 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section { case 0: return 1; case 1: return result.issues.count; case 2: return result.balances.count; default: return result.issues.isEmpty ? max(result.transfers.count, 1) + 1 + (receipt.reviewed ? 1 : 0) : 0 }
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section { case 0: return "RECEIPT TOTAL"; case 1: return result.issues.isEmpty ? nil : "Before settling"; case 2: return "Each person’s share"; default: return result.issues.isEmpty ? "Settle up" : nil }
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 { return "Adjustments are shared in proportion to each person’s items. Every paise is accounted for." }
        if section == 3 && result.issues.isEmpty { return "Confirm you checked the receipt and all assignments. ReceiptSplit does not transfer money." }
        return nil
    }
    override func tableView(_ tableView: UITableView, cellForRowAt p: IndexPath) -> UITableViewCell {
        let result = result
        switch p.section {
        case 0: return cell(result.issues.isEmpty ? "All numbers checked" : "A few things to check", detail: Money.format(receipt.total), symbol: result.issues.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
        case 1: let c = cell(result.issues[p.row], symbol: "exclamationmark.circle"); c.heading.numberOfLines = 0; return c
        case 2:
            let person = result.balances[p.row]
            return cell("\(person.name) · \(Money.format(person.owed))", detail: "Paid \(Money.format(person.paid)) · " + (person.balance >= 0 ? "Gets back \(Money.format(person.balance))" : "Still owes \(Money.format(-person.balance))"), symbol: "person.crop.circle.fill")
        default:
            let transferCount = max(result.transfers.count, 1)
            if p.row < transferCount {
                if result.transfers.isEmpty { return cell("Everyone is settled") }
                let transfer = result.transfers[p.row]
                return cell("\(transfer.from) pays \(transfer.to)", detail: Money.format(transfer.amount), symbol: "arrow.right.circle.fill")
            }
            if p.row == transferCount { return cell(receipt.reviewed ? "Receipt verified" : "Confirm review", id: "confirmReview", symbol: "checkmark.circle") }
            return cell("Share settlement", id: "shareSettlement", symbol: "square.and.arrow.up")
        }
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt p: IndexPath) {
        tableView.deselectRow(at: p, animated: true)
        let result = result; guard p.section == 3 && result.issues.isEmpty else { return }
        let transferCount = max(result.transfers.count, 1)
        if p.row == transferCount && !receipt.reviewed {
            receipt.reviewed = true; if saveChanges() { tableView.reloadData() }
        } else if p.row == transferCount + 1 && receipt.reviewed {
            let sheet = UIActivityViewController(activityItems: [SplitEngine.summary(receipt)], applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = tableView.cellForRow(at: p); present(sheet, animated: true)
        }
    }
}

final class OCRReviewViewController: StoryboardTableController {
    var receipt: Receipt!
    var draft: OCRDraft!
    private var selected: Set<UUID> = []
    private var useMerchant = false
    private var useTotal = false
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Review scan"; navigationItem.largeTitleDisplayMode = .never
        selected = Set(draft.lines.map(\.id))
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Import", style: .done, target: self, action: #selector(importItems))
        refreshImportButton()
    }
    func refreshImportButton() { navigationItem.rightBarButtonItem?.isEnabled = !selected.isEmpty || useMerchant || useTotal }
    override func numberOfSections(in tableView: UITableView) -> Int { 4 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section { case 0: return 1; case 1: return draft.total == nil ? 1 : 2; case 2: return max(draft.lines.count, 1); default: return 1 }
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section { case 0: return "Review before importing"; case 1: return "Detected fields"; case 2: return "Detected items"; default: return "Recognized text" }
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 ? "OCR can misread values. Amounts are treated as line totals with quantity 1. Check each imported item and enter taxes and discounts manually." : nil
    }
    override func tableView(_ tableView: UITableView, cellForRowAt p: IndexPath) -> UITableViewCell {
        switch p.section {
        case 0: return cell("Select fields and items to import")
        case 1:
            if p.row == 0 { return cell("Use merchant: \(draft.merchant)", accessory: useMerchant ? .checkmark : .none) }
            return cell("Use printed total: \(Money.format(draft.total!))", accessory: useTotal ? .checkmark : .none)
        case 2:
            guard !draft.lines.isEmpty else { return cell("No item rows detected. Enter items manually.") }
            let line = draft.lines[p.row]
            return cell(line.name, detail: "\(Money.format(line.amount)) · \(line.confidence < 0.8 ? "Low confidence" : "Check against receipt")", accessory: selected.contains(line.id) ? .checkmark : .none)
        default:
            let c = cell(draft.rawText); c.heading.numberOfLines = 0; c.heading.font = .monospacedSystemFont(ofSize: 13, weight: .regular); return c
        }
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt p: IndexPath) {
        tableView.deselectRow(at: p, animated: true)
        if p.section == 1 { if p.row == 0 { useMerchant.toggle() } else { useTotal.toggle() } }
        if p.section == 2 && !draft.lines.isEmpty { let id = draft.lines[p.row].id; if selected.contains(id) { selected.remove(id) } else { selected.insert(id) } }
        refreshImportButton(); tableView.reloadData()
    }
    @objc func importItems() {
        for line in draft.lines where selected.contains(line.id) {
            let item = ReceiptItem(name: line.name, unitPrice: line.amount); item.needsReview = true; receipt.items.append(item)
        }
        if useMerchant { receipt.merchant = draft.merchant }; if useTotal { receipt.printedTotal = draft.total }; receipt.reviewed = false; popIfSaved()
    }
}
