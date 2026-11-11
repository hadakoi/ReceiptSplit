import UIKit

final class ItemEditorViewController: StoryboardTableController {
    var receipt: Receipt!
    var item: ReceiptItem?
    private var mode = "equal"
    private var everyone = true
    private var shares: [String: String] = [:]
    private let modes = [("Equal", "equal"), ("By quantity", "quantity"), ("Weighted", "weighted"), ("Custom amounts", "custom")]
    override func viewDidLoad() {
        super.viewDidLoad(); title = item == nil ? "Add item" : "Edit item"; editorButtons(saveID: "saveItem")
        stageHeader("Assign item shares", subtitle: "Choose who shared this item and how to divide it.", symbol: "chart.pie.fill", color: .systemOrange)
        values = ["Name": item?.name ?? "", "Quantity": String(item?.quantity ?? 1), "Unit price": item.map { Money.edit($0.unitPrice) } ?? ""]
        if let item { mode = item.splitMode; everyone = item.allocations.isEmpty; shares = item.allocations.mapValues { mode == "custom" ? Money.edit($0) : String($0) } }
        inputChanged()
    }
    override func inputChanged() { navigationItem.rightBarButtonItem?.isEnabled = !(values["Name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return 3 }
        if receipt.people.isEmpty { return 2 }
        return 1 + (mode == "equal" ? 1 + (everyone ? 0 : receipt.people.count) : receipt.people.count)
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { section == 0 ? "Line item" : "Who shares this item?" }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 1 else { return item?.needsReview == true ? "Saving confirms the scanned name, quantity and price." : nil }
        switch mode { case "quantity": return "Assign whole units; their sum must equal the quantity."; case "weighted": return "Use weights 1:1 for halves, 1:2 for one third and two thirds, or 1:3 for a quarter and three quarters."; case "custom": return "Amounts must add up to the line total."; default: return "Share equally with everyone or choose participants. Two, three or four people get halves, thirds or quarters." }
    }
    override func tableView(_ tableView: UITableView, cellForRowAt p: IndexPath) -> UITableViewCell {
        if p.section == 0 {
            switch p.row { case 0: return field("Name", placeholder: "Item name", id: "itemNameField"); case 1: return field("Quantity", placeholder: "1", keyboard: .numberPad, id: "quantityField"); default: return field("Unit price", placeholder: "0.00", keyboard: .decimalPad) }
        }
        if p.row == 0 { return cell("Split method", detail: modes.first { $0.1 == mode }?.0, accessory: .disclosureIndicator, id: "splitMethod", symbol: "slider.horizontal.3", tint: .systemOrange) }
        if receipt.people.isEmpty { return cell("Add participants to assign this item.") }
        if mode == "equal" && p.row == 1 { return cell("Share with everyone", accessory: everyone ? .checkmark : .none, id: "shareEveryone") }
        let person = receipt.people[p.row - (mode == "equal" ? 2 : 1)]
        if mode == "equal" { return cell(person.name, accessory: shares[person.id.uuidString] == "1" ? .checkmark : .none, id: "share-" + person.name) }
        let c = tableView.dequeueReusableCell(withIdentifier: "InputCell") as! StoryboardInputCell
        c.heading.text = person.name
        let input = c.input!
        input.text = shares[person.id.uuidString] ?? ""; input.placeholder = mode == "custom" ? "0.00" : "0"; input.keyboardType = mode == "custom" ? .decimalPad : .numberPad
        input.textAlignment = .right; input.accessibilityIdentifier = "share-" + person.name; input.accessibilityLabel = "Share for \(person.name)"
        c.onChange = { [weak self] text in self?.shares[person.id.uuidString] = text }
        return c
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt p: IndexPath) {
        tableView.deselectRow(at: p, animated: true); guard p.section == 1 else { return }
        if p.row == 0 {
            let menu = UIAlertController(title: "Split method", message: nil, preferredStyle: .actionSheet)
            for (name, value) in modes { menu.addAction(UIAlertAction(title: name, style: .default) { _ in self.mode = value; self.shares = [:]; self.everyone = true; self.tableView.reloadData() }) }
            menu.addAction(UIAlertAction(title: "Cancel", style: .cancel)); menu.popoverPresentationController?.sourceView = tableView.cellForRow(at: p); present(menu, animated: true); return
        }
        guard !receipt.people.isEmpty, mode == "equal" else { return }
        if p.row == 1 { everyone.toggle() }
        else { let key = receipt.people[p.row - 2].id.uuidString; shares[key] = shares[key] == "1" ? "0" : "1" }
        tableView.reloadSections(IndexSet(integer: 1), with: .automatic)
    }
    override func savePressed() {
        guard let quantity = Int(values["Quantity"] ?? ""), (1...999).contains(quantity), let price = amount("Unit price") else { showError("Enter a quantity from 1 to 999 and a valid unit price."); return }
        var allocations: [String: Int] = [:]
        if !(mode == "equal" && everyone) && !receipt.people.isEmpty {
            for person in receipt.people {
                let key = person.id.uuidString, text = shares[key].flatMap { $0.isEmpty ? nil : $0 } ?? "0"
                guard let n = mode == "custom" ? Money.parse(text) : Int(text), (0...1_000_000_000).contains(n) else { showError("Enter a valid non-negative share for \(person.name)."); return }
                allocations[key] = n
            }
            let sum = allocations.values.reduce(0, +)
            if mode == "custom" && sum != quantity * price { showError("Custom amounts must equal \(Money.format(quantity * price))."); return }
            if mode == "quantity" && sum != quantity { showError("Assigned quantities must total \(quantity)."); return }
            if mode != "custom" && sum == 0 { showError("Choose at least one participant or enter positive weights."); return }
        }
        let target = item ?? ReceiptItem(name: "", unitPrice: price)
        if item == nil { receipt.items.append(target) }
        target.name = (values["Name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines); target.quantity = quantity; target.unitPrice = price
        target.splitMode = mode; target.allocations = allocations; target.needsReview = false; receipt.reviewed = false; popIfSaved()
    }
}
