import UIKit
import SwiftData
import PhotosUI
import VisionKit

final class ReceiptsViewController: StoryboardTableController, UISearchResultsUpdating {
    private var receipts: [Receipt] = []
    private let search = UISearchController(searchResultsController: nil)
    override func viewDidLoad() {
        super.viewDidLoad(); title = "ReceiptSplit"; navigationController?.navigationBar.prefersLargeTitles = true
        let add = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addReceipt)); add.accessibilityLabel = "New receipt"
        navigationItem.rightBarButtonItem = add
        search.searchResultsUpdater = self; search.searchBar.placeholder = "Find a merchant"; navigationItem.searchController = search
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); reload() }
    func reload() {
        do { receipts = try store.fetch(FetchDescriptor<Receipt>(sortBy: [SortDescriptor(\.date, order: .reverse)])) } catch { showError(error.localizedDescription) }
        tableView.reloadData()
    }
    var visible: [Receipt] { let text = search.searchBar.text ?? ""; return receipts.filter { text.isEmpty || $0.merchant.localizedCaseInsensitiveContains(text) } }
    func updateSearchResults(for searchController: UISearchController) { tableView.reloadData() }
    @objc func addReceipt() { performSegue(withIdentifier: "editReceipt", sender: nil) }
    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 2 : max(visible.count, 1) }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { section == 0 ? "ON YOUR DEVICE" : "Your receipts" }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            if indexPath.row == 1 { return cell("Try a sample split", detail: "Create an example to explore the whole flow", accessory: .disclosureIndicator, id: "sampleSplit", symbol: "sparkles") }
            return cell("Good meals. Clear splits.", detail: "\(receipts.count) receipts · \(Money.format(receipts.reduce(0) { $0 + $1.total }))", symbol: "receipt")
        }
        guard !visible.isEmpty else { return cell(search.searchBar.text?.isEmpty == false ? "No matching receipts" : "Your next split starts here", detail: "Tap + to add your first receipt.") }
        let r = visible[indexPath.row]
        return cell(r.merchant, detail: "\(r.date.formatted(date: .abbreviated, time: .omitted)) · \(r.items.count) items · \(Money.format(r.total)) · \(r.reviewed ? "Ready" : "Draft")", accessory: .disclosureIndicator, id: "receipt-" + r.merchant)
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 && indexPath.row == 1 {
            let sample = Receipt(merchant: "Sample Café")
            sample.printedTotal = 31950; sample.cgst = 750; sample.sgst = 750; sample.service = 1500; sample.discount = 1000; sample.rounding = -50
            sample.items = [ReceiptItem(name: "Lunch", unitPrice: 20000), ReceiptItem(name: "Dessert", unitPrice: 10000)]
            sample.people = [Participant(name: "Alex", paid: 31950), Participant(name: "Sam")]
            store.insert(sample)
            if saveChanges() { reload(); performSegue(withIdentifier: "showReceipt", sender: sample) }
        } else if indexPath.section == 1 && !visible.isEmpty { performSegue(withIdentifier: "showReceipt", sender: visible[indexPath.row]) }
    }
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 1 && !visible.isEmpty else { return nil }
        let receipt = visible[indexPath.row]
        return UISwipeActionsConfiguration(actions: [UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            self?.confirm("Delete receipt?", message: "This removes its items and participants from this device.") {
                self?.store.delete(receipt); if self?.saveChanges() == true { self?.reload() }
            }; done(true)
        }])
    }
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let vc = segue.destination as? DetailViewController { vc.receipt = sender as? Receipt }
    }
}

final class ReceiptEditorViewController: StoryboardTableController {
    var receipt: Receipt?
    private var date = Date()
    let keys = ["Name", "Date", "Notes", "Printed total", "CGST", "SGST", "Service charge", "Tip", "Discount", "Rounding"]
    override func viewDidLoad() {
        super.viewDidLoad(); title = receipt == nil ? "New receipt" : "Edit receipt"; editorButtons(saveID: "saveReceipt")
        if let r = receipt {
            values = ["Name": r.merchant, "Notes": r.notes, "Printed total": r.printedTotal.map(Money.edit) ?? "", "CGST": Money.edit(r.cgst), "SGST": Money.edit(r.sgst), "Service charge": Money.edit(r.service), "Tip": Money.edit(r.tip), "Discount": Money.edit(r.discount), "Rounding": Money.edit(r.rounding)]; date = r.date
        } else { for key in keys.dropFirst(4) { values[key] = "0.00" } }
        inputChanged()
    }
    override func inputChanged() { navigationItem.rightBarButtonItem?.isEnabled = !(values["Name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { keys.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let key = keys[indexPath.row]
        if key == "Date" {
            let c = cell("Date"); let picker = UIDatePicker(); picker.tag = 977; picker.datePickerMode = .date; picker.preferredDatePickerStyle = .compact; picker.date = date
            picker.addAction(UIAction { [weak self, weak picker] _ in self?.date = picker?.date ?? Date() }, for: .valueChanged)
            picker.translatesAutoresizingMaskIntoConstraints = false; c.contentView.addSubview(picker)
            NSLayoutConstraint.activate([picker.trailingAnchor.constraint(equalTo: c.contentView.layoutMarginsGuide.trailingAnchor), picker.centerYAnchor.constraint(equalTo: c.contentView.centerYAnchor)])
            return c
        }
        return field(key, placeholder: key == "Name" ? "Merchant name" : key == "Notes" ? "Optional" : "0.00", keyboard: key == "Rounding" ? .numbersAndPunctuation : indexPath.row >= 3 ? .decimalPad : .default, id: key == "Name" ? "merchantField" : nil)
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { "Enter amounts in INR. For tax-inclusive prices, do not add GST again. Rounding can be negative." }
    override func savePressed() {
        guard let a = amount("CGST"), let b = amount("SGST"), let c = amount("Service charge"), let d = amount("Tip"), let e = amount("Discount"), let f = amount("Rounding", signed: true), (values["Printed total"] ?? "").isEmpty || amount("Printed total") != nil else { showError("Use valid amounts with up to two decimal places. Only rounding can be negative."); return }
        let target = receipt ?? Receipt(merchant: "")
        if receipt == nil { store.insert(target) }
        target.merchant = (values["Name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines); target.date = date; target.notes = values["Notes"] ?? ""
        target.cgst = a; target.sgst = b; target.service = c; target.tip = d; target.discount = e; target.rounding = f
        target.printedTotal = amount("Printed total"); target.reviewed = false
        popIfSaved()
    }
}
