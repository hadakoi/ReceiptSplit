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
    var isNewReceipt = false
    private var selected: Set<UUID> = []
    private var selectedCharges: Set<UUID> = []
    private var useMerchant = false
    private var useTotal = false
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Review scan"; navigationItem.largeTitleDisplayMode = .never
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 56
        selected = Set(draft.lines.map(\.id))
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Import", style: .done, target: self, action: #selector(importItems))
        refreshImportButton()
    }
    func refreshImportButton() { navigationItem.rightBarButtonItem?.isEnabled = !selected.isEmpty || !selectedCharges.isEmpty || useMerchant || useTotal }
    override func numberOfSections(in tableView: UITableView) -> Int { 5 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section { case 0: return 1; case 1: return draft.total == nil ? 1 : 2; case 2: return max(draft.lines.count, 1); case 3: return max(draft.charges.count, 1); default: return 1 }
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section { case 0: return "Review before importing"; case 1: return "Detected fields"; case 2: return "Detected items"; case 3: return "Suggested charges"; default: return "Recognized text" }
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 { return "OCR can misread values. Check every item and amount against the receipt; quantities are suggested only when the numbers agree." }
        if section == 3 { return "Charges are unselected until you choose them. Select only amounts added to the bill, not tax already included in item prices. Review or add missing amounts in Edit receipt." }
        return nil
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
            let amount = line.unitPrice.map { "\(line.quantity) × \(Money.format($0)) = \(Money.format(line.amount))" } ?? Money.format(line.amount)
            return cell(line.name, detail: "\(amount) · \(line.confidence < 0.8 ? "Low confidence" : "Check against receipt")", accessory: selected.contains(line.id) ? .checkmark : .none)
        case 3:
            guard !draft.charges.isEmpty else { return cell("No charges detected. Enter any missing amounts manually.") }
            let charge = draft.charges[p.row]
            let duplicates = draft.charges.filter { $0.kind == charge.kind }.count > 1
            let c = cell("\(charge.kind.rawValue) · \(Money.format(charge.amount))", detail: "\(charge.source)\(duplicates ? " · Multiple candidates" : "")\(charge.confidence < 0.8 ? " · Low confidence" : "")", accessory: selectedCharges.contains(charge.id) ? .checkmark : .none)
            c.detail.numberOfLines = 0
            return c
        default:
            let c = cell(draft.rawText); c.heading.numberOfLines = 0; c.heading.lineBreakMode = .byWordWrapping; c.heading.font = .monospacedSystemFont(ofSize: 13, weight: .regular); return c
        }
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt p: IndexPath) {
        tableView.deselectRow(at: p, animated: true)
        if p.section == 1 { if p.row == 0 { useMerchant.toggle() } else { useTotal.toggle() } }
        if p.section == 2 && !draft.lines.isEmpty { let id = draft.lines[p.row].id; if selected.contains(id) { selected.remove(id) } else { selected.insert(id) } }
        if p.section == 3 && !draft.charges.isEmpty {
            let charge = draft.charges[p.row]
            if selectedCharges.contains(charge.id) { selectedCharges.remove(charge.id) }
            else { for other in draft.charges where other.kind == charge.kind { selectedCharges.remove(other.id) }; selectedCharges.insert(charge.id) }
        }
        refreshImportButton(); tableView.reloadData()
    }
    @objc func importItems() {
        let chosen = draft.charges.filter { selectedCharges.contains($0.id) }
        let replacesCharges = chosen.contains { existingAmount($0.kind) != 0 }
        let addsToItems = !receipt.items.isEmpty && !selected.isEmpty
        if replacesCharges || addsToItems {
            var notes: [String] = []
            if addsToItems { notes.append("Selected scan items will be added to the \(receipt.items.count) items already on this receipt.") }
            if replacesCharges { notes.append("Selected scan amounts will replace the corresponding charges already entered.") }
            let alert = UIAlertController(title: "Import into this receipt?", message: notes.joined(separator: "\n\n"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Import", style: .default) { _ in self.finishImport(chosen) })
            present(alert, animated: true); return
        }
        finishImport(chosen)
    }
    private func existingAmount(_ kind: OCRChargeKind) -> Int {
        switch kind { case .cgst: return receipt.cgst; case .sgst: return receipt.sgst; case .service: return receipt.service; case .discount: return receipt.discount; case .rounding: return receipt.rounding; case .tip: return receipt.tip }
    }
    private func finishImport(_ charges: [OCRCharge]) {
        for line in draft.lines where selected.contains(line.id) {
            let item = ReceiptItem(name: line.name, quantity: line.quantity, unitPrice: line.unitPrice ?? line.amount); item.needsReview = true; receipt.items.append(item)
        }
        for charge in charges {
            switch charge.kind { case .cgst: receipt.cgst = charge.amount; case .sgst: receipt.sgst = charge.amount; case .service: receipt.service = charge.amount; case .discount: receipt.discount = charge.amount; case .rounding: receipt.rounding = charge.amount; case .tip: receipt.tip = charge.amount }
        }
        if useMerchant { receipt.merchant = draft.merchant }; if useTotal { receipt.printedTotal = draft.total }; receipt.reviewed = false
        if isNewReceipt {
            store.insert(receipt)
            if saveChanges(), let nav = navigationController {
                nav.popViewController(animated: false)
                (nav.topViewController as? ReceiptsViewController)?.openReceipt(receipt)
            }
        } else { popIfSaved() }
    }
}
