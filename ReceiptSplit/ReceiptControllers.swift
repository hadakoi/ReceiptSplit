import UIKit
import SwiftData
import PhotosUI
import VisionKit

final class ReceiptsViewController: StoryboardTableController, UISearchResultsUpdating, VNDocumentCameraViewControllerDelegate, PHPickerViewControllerDelegate {
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
    @objc func addReceipt() {
        let menu = UIAlertController(title: "New receipt", message: "How would you like to start?", preferredStyle: .actionSheet)
        if VNDocumentCameraViewController.isSupported { menu.addAction(UIAlertAction(title: "Scan receipt", style: .default) { _ in self.startScan() }) }
        menu.addAction(UIAlertAction(title: "Import receipt photo", style: .default) { _ in self.startPhotoImport() })
        menu.addAction(UIAlertAction(title: "Enter manually", style: .default) { _ in self.performSegue(withIdentifier: "editReceipt", sender: nil) })
        menu.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        menu.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(menu, animated: true)
    }
    private func startScan() {
        guard VNDocumentCameraViewController.isSupported else { startPhotoImport(); return }
        let scanner = VNDocumentCameraViewController(); scanner.delegate = self; present(scanner, animated: true)
    }
    private func startPhotoImport() {
        var config = PHPickerConfiguration(); config.filter = .images; config.selectionLimit = 1; config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config); picker.delegate = self; present(picker, animated: true)
    }
    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { controller.dismiss(animated: true) }
    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { controller.dismiss(animated: true) { self.showError(error.localizedDescription) } }
    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
        let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
        controller.dismiss(animated: true) { self.recognize(images) }
    }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true) { [weak self] in
            guard let self, let provider = results.first?.itemProvider else { return }
            self.loadReceiptPhoto(provider) { [weak self] draft in self?.performSegue(withIdentifier: "reviewNewOCR", sender: draft) }
        }
    }
    private func recognize(_ images: [UIImage]) {
        let progress = UIAlertController(title: "Reading receipt on device…", message: nil, preferredStyle: .alert)
        present(progress, animated: true)
        Task { @MainActor in
            do { let draft = try await ReceiptOCR.recognize(images); progress.dismiss(animated: true) { self.performSegue(withIdentifier: "reviewNewOCR", sender: draft) } }
            catch { progress.dismiss(animated: true) { self.showError(error.localizedDescription) } }
        }
    }
    func openReceipt(_ receipt: Receipt) { performSegue(withIdentifier: "showReceipt", sender: receipt) }
    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 3 : max(visible.count, 1) }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { section == 0 ? "ON YOUR DEVICE" : "Your receipts" }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { section == 1 && !visible.isEmpty ? "Swipe left on a receipt to mark it settled, reopen it, or delete it." : nil }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            if indexPath.row == 1 { return cell(VNDocumentCameraViewController.isSupported ? "Scan a receipt" : "Import receipt photo", detail: "Start a new split from a receipt", accessory: .disclosureIndicator, id: "scanReceipt", symbol: "camera.viewfinder") }
            if indexPath.row == 2 { return cell("Saved people", detail: "Manage people you split with", accessory: .disclosureIndicator, id: "manageSavedPeople", symbol: "person.2.fill") }
            return cell("Your overview", detail: "\(receipts.count) receipts · \(Money.format(receipts.reduce(0) { $0 + $1.total }))", symbol: "receipt")
        }
        guard !visible.isEmpty else { return cell(search.searchBar.text?.isEmpty == false ? "No matching receipts" : "Your next split starts here", detail: "Tap + to add your first receipt.") }
        let r = visible[indexPath.row]
        return cell(r.merchant, detail: "\(SettlementStatus.isSettled(r) ? "Settled" : r.reviewed ? "Ready" : "Draft") · \(Money.format(r.total)) · \(r.date.formatted(date: .abbreviated, time: .omitted))", accessory: .disclosureIndicator, id: "receipt-" + r.merchant)
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 && indexPath.row == 1 {
            startScan()
        } else if indexPath.section == 0 && indexPath.row == 2 { performSegue(withIdentifier: "manageSavedPeople", sender: nil) }
        else if indexPath.section == 1 && !visible.isEmpty { performSegue(withIdentifier: "showReceipt", sender: visible[indexPath.row]) }
    }
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 1 && !visible.isEmpty else { return nil }
        let receipt = visible[indexPath.row]
        let toggle = UIContextualAction(style: .normal, title: SettlementStatus.isSettled(receipt) ? "Reopen" : "Mark settled") { [weak self] _, _, done in
            guard let self else { done(false); return }
            if SettlementStatus.isSettled(receipt) { SettlementStatus.clear(receipt) }
            else if !SettlementStatus.markSettled(receipt) { self.showError("Review and confirm this receipt in Split & settle before marking it settled."); done(false); return }
            self.tableView.reloadData(); done(true)
        }
        toggle.backgroundColor = .systemGreen
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            self?.confirm("Delete receipt?", message: "This removes its items and participants from this device.") {
                self?.store.delete(receipt); if self?.saveChanges() == true { SettlementStatus.clear(receipt); self?.reload() }
            }; done(true)
        }
        let actions = UISwipeActionsConfiguration(actions: [toggle, delete]); actions.performsFirstActionWithFullSwipe = false; return actions
    }
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let vc = segue.destination as? DetailViewController { vc.receipt = sender as? Receipt }
        if let vc = segue.destination as? OCRReviewViewController, let draft = sender as? OCRDraft {
            vc.draft = draft; vc.receipt = Receipt(merchant: draft.merchant); vc.isNewReceipt = true
        }
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
