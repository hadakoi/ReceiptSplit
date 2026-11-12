import UIKit

final class ItemEditorViewController: StoryboardTableController {
    var receipt: Receipt!
    var item: ReceiptItem?
    private var mode = "equal"
    private var selected: Set<String> = []
    private var shares: [String: String] = [:]
    private let modes = [("Equal", "equal"), ("Percentages", "weighted"), ("By quantity", "quantity"), ("Custom amounts", "custom")]
    private var chosen: [Participant] { receipt.people.filter { selected.contains($0.id.uuidString) } }

    override func viewDidLoad() {
        super.viewDidLoad(); title = item == nil ? "Add item" : "Edit item"; editorButtons(saveID: "saveItem")
        values = ["Name": item?.name ?? "", "Quantity": String(item?.quantity ?? 1), "Unit price": item.map { Money.edit($0.unitPrice) } ?? ""]
        if let item {
            mode = item.splitMode
            let allocations = item.allocations
            selected = Set(receipt.people.filter { allocations.isEmpty || (allocations[$0.id.uuidString] ?? 0) > 0 }.map { $0.id.uuidString })
            if mode == "weighted" {
                let people = receipt.people.filter { selected.contains($0.id.uuidString) }
                let percentages = SplitEngine.distribute(10000, weights: people.map { allocations[$0.id.uuidString] ?? 0 })
                for (index, person) in people.enumerated() { shares[person.id.uuidString] = Money.edit(percentages[index]) }
            } else { shares = allocations.mapValues { mode == "custom" ? Money.edit($0) : String($0) } }
        } else { selected = Set(receipt.people.map { $0.id.uuidString }) }
        inputChanged()
    }
    override func inputChanged() { navigationItem.rightBarButtonItem?.isEnabled = !(values["Name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    override func numberOfSections(in tableView: UITableView) -> Int { 3 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return 3 }
        if section == 1 { return max(receipt.people.count, 1) }
        guard chosen.count > 1 else { return 0 }
        return 1 + (mode == "equal" ? 0 : chosen.count)
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 { return "Line item" }; if section == 1 { return "Who had this item?" }; return chosen.count > 1 ? "How is it split?" : nil
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 { return item?.needsReview == true ? "Saving confirms the scanned name, quantity and price." : nil }
        if section == 1 { return receipt.people.isEmpty ? "Add participants to this receipt first." : chosen.count == 1 ? "One person selected; they receive the whole item." : "Select everyone who shared this item." }
        guard chosen.count > 1 else { return nil }
        switch mode { case "quantity": return "Assign whole units; their sum must equal the quantity."; case "weighted": return "Enter percentages that add up to 100%, such as 75 and 25. Up to two decimal places are supported."; case "custom": return "Amounts must add up to the line total."; default: return "The selected people share this item equally." }
    }
    override func tableView(_ tableView: UITableView, cellForRowAt p: IndexPath) -> UITableViewCell {
        if p.section == 0 {
            switch p.row { case 0: return field("Name", placeholder: "Item name", id: "itemNameField"); case 1: return field("Quantity", placeholder: "1", keyboard: .numberPad, id: "quantityField"); default: return field("Unit price", placeholder: "0.00", keyboard: .decimalPad) }
        }
        if p.section == 1 {
            guard !receipt.people.isEmpty else { return cell("Add participants to assign this item.") }
            let person = receipt.people[p.row]
            return cell(person.name, accessory: selected.contains(person.id.uuidString) ? .checkmark : .none, id: "select-" + person.name)
        }
        if p.row == 0 { return cell("Split method", detail: modes.first { $0.1 == mode }?.0, accessory: .disclosureIndicator, id: "splitMethod", symbol: "slider.horizontal.3") }
        let person = chosen[p.row - 1]
        let c = tableView.dequeueReusableCell(withIdentifier: "InputCell") as! StoryboardInputCell
        c.heading.text = mode == "weighted" ? person.name + " (%)" : person.name
        let input = c.input!
        input.text = shares[person.id.uuidString] ?? ""; input.placeholder = mode == "quantity" ? "0" : "0.00"; input.keyboardType = mode == "quantity" ? .numberPad : .decimalPad
        input.textAlignment = .right; input.accessibilityIdentifier = "share-" + person.name; input.accessibilityLabel = mode == "weighted" ? "Percentage for \(person.name)" : "Share for \(person.name)"
        c.onChange = { [weak self] text in self?.shares[person.id.uuidString] = text }
        return c
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt p: IndexPath) {
        tableView.deselectRow(at: p, animated: true)
        if p.section == 1, !receipt.people.isEmpty {
            let key = receipt.people[p.row].id.uuidString
            if selected.contains(key) { selected.remove(key) } else { selected.insert(key) }
            if chosen.count < 2 { mode = "equal"; shares = [:] }
            tableView.reloadSections(IndexSet([1, 2]), with: .automatic); return
        }
        if p.section == 2 && p.row == 0 {
            let menu = UIAlertController(title: "Split method", message: nil, preferredStyle: .actionSheet)
            for (name, value) in modes { menu.addAction(UIAlertAction(title: name, style: .default) { _ in self.mode = value; self.shares = [:]; self.tableView.reloadData() }) }
            menu.addAction(UIAlertAction(title: "Cancel", style: .cancel)); menu.popoverPresentationController?.sourceView = tableView.cellForRow(at: p); present(menu, animated: true)
        }
    }
    override func savePressed() {
        guard let quantity = Int(values["Quantity"] ?? ""), (1...999).contains(quantity), let price = amount("Unit price") else { showError("Enter a quantity from 1 to 999 and a valid unit price."); return }
        guard receipt.people.isEmpty || !chosen.isEmpty else { showError("Select at least one person for this item."); return }
        var allocations: [String: Int] = [:]
        let effectiveMode = chosen.count <= 1 ? "equal" : mode
        if !receipt.people.isEmpty {
            for person in chosen {
                let key = person.id.uuidString
                if effectiveMode == "equal" { allocations[key] = 1; continue }
                let text = shares[key].flatMap { $0.isEmpty ? nil : $0 } ?? "0"
                let n = effectiveMode == "quantity" ? Int(text) : Money.parse(text)
                guard let n, (0...1_000_000_000).contains(n) else { showError("Enter a valid non-negative share for \(person.name)."); return }
                allocations[key] = n
            }
            let sum = allocations.values.reduce(0, +)
            if effectiveMode == "weighted" && (sum != 10000 || allocations.values.contains(0)) { showError("Enter a positive percentage for each selected person; the total must be 100%."); return }
            if effectiveMode == "custom" && sum != quantity * price { showError("Custom amounts must equal \(Money.format(quantity * price))."); return }
            if effectiveMode == "quantity" && sum != quantity { showError("Assigned quantities must total \(quantity)."); return }
        }
        let target = item ?? ReceiptItem(name: "", unitPrice: price)
        if item == nil { receipt.items.append(target) }
        target.name = (values["Name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines); target.quantity = quantity; target.unitPrice = price
        target.splitMode = effectiveMode; target.allocations = allocations; target.needsReview = false; receipt.reviewed = false; popIfSaved()
    }
}
