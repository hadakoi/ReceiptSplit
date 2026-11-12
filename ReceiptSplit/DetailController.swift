import UIKit
import PhotosUI
import VisionKit

final class DetailViewController: StoryboardTableController, VNDocumentCameraViewControllerDelegate, PHPickerViewControllerDelegate {
    var receipt: Receipt!
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(editReceipt))
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); title = receipt.merchant; tableView.reloadData() }
    @objc func editReceipt() { performSegue(withIdentifier: "editReceipt", sender: receipt) }
    override func numberOfSections(in tableView: UITableView) -> Int { receipt.notes.isEmpty ? 5 : 6 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section { case 0: return 2; case 1: return 2; case 2: return receipt.items.count + 1; case 3: return VNDocumentCameraViewController.isSupported ? 2 : 1; case 4: return 9; default: return 1 }
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section { case 0: return receipt.reviewed ? "READY TO SETTLE" : "RECEIPT IN REVIEW"; case 1: return "Split"; case 2: return "Items"; case 3: return "Receipt capture"; case 4: return "Bill breakdown"; default: return "Notes" }
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section { case 2: return "Tap an item to edit it and choose who shares it. Adjustments follow each person’s item subtotal."; case 3: return "Photos are processed on this device. Review every detected item."; default: return nil }
    }
    override func tableView(_ tableView: UITableView, cellForRowAt p: IndexPath) -> UITableViewCell {
        switch p.section {
        case 0:
            if p.row == 0 { return cell(Money.format(receipt.total), detail: receipt.date.formatted(date: .long, time: .omitted), id: "receiptTotal") }
            let message = receipt.difference.map { $0 == 0 ? "Matches printed total" : "Difference: \(Money.format($0))" } ?? "Add the printed total to reconcile"
            return cell(message)
        case 1:
            return p.row == 0 ? cell("Participants · \(receipt.people.count)", detail: "Add people and record who paid", accessory: .disclosureIndicator, id: "participantsLink", symbol: "person.2.fill") : cell("Review split & settle", detail: "Check shares and see who pays whom", accessory: .disclosureIndicator, id: "settlementLink", symbol: "arrow.left.arrow.right")
        case 2:
            guard p.row < receipt.items.count else { return cell("Add item", accessory: .disclosureIndicator, id: "addItem", symbol: "plus.circle.fill") }
            let item = receipt.items[p.row]
            return cell(item.name, detail: "\(item.quantity) × \(Money.format(item.unitPrice)) · \(item.splitMode.capitalized) · \(Money.format(item.total))\(item.needsReview ? " · Check scanned value" : "")", accessory: .disclosureIndicator, id: "item-" + item.name, symbol: "fork.knife")
        case 3:
            return cell(VNDocumentCameraViewController.isSupported && p.row == 0 ? "Scan receipt" : "Import receipt photo", accessory: .disclosureIndicator, symbol: "camera.viewfinder")
        case 5:
            let result = cell(receipt.notes); result.heading.numberOfLines = 0; return result
        default:
            let rows: [(String, Int)] = [("Subtotal", receipt.subtotal), ("CGST", receipt.cgst), ("SGST", receipt.sgst), ("Service charge", receipt.service), ("Tip", receipt.tip), ("Discount", -receipt.discount), ("Rounding", receipt.rounding), ("Printed total", receipt.printedTotal ?? 0)]
            if p.row == 8 { return cell("Edit receipt & adjustments", accessory: .disclosureIndicator, symbol: "slider.horizontal.3") }
            return cell(rows[p.row].0, detail: p.row == 7 && receipt.printedTotal == nil ? "Not entered" : Money.format(rows[p.row].1))
        }
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt p: IndexPath) {
        tableView.deselectRow(at: p, animated: true)
        switch p.section {
        case 1: performSegue(withIdentifier: p.row == 0 ? "showPeople" : "showSettlement", sender: nil)
        case 2: performSegue(withIdentifier: "editItem", sender: p.row < receipt.items.count ? receipt.items[p.row] : nil)
        case 3:
            if VNDocumentCameraViewController.isSupported && p.row == 0 {
                let scanner = VNDocumentCameraViewController(); scanner.delegate = self; present(scanner, animated: true)
            } else {
                var config = PHPickerConfiguration(); config.filter = .images; config.selectionLimit = 1; config.preferredAssetRepresentationMode = .current
                let picker = PHPickerViewController(configuration: config); picker.delegate = self; present(picker, animated: true)
            }
        case 4 where p.row == 8: editReceipt()
        default: break
        }
    }
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt p: IndexPath) -> UISwipeActionsConfiguration? {
        guard p.section == 2, p.row < receipt.items.count else { return nil }
        let item = receipt.items[p.row]
        return UISwipeActionsConfiguration(actions: [UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            self?.confirm("Delete item?", message: "This removes the item from the receipt.") {
                guard let self else { return }; self.receipt.items.removeAll { $0.id == item.id }; self.store.delete(item); self.receipt.reviewed = false
                if self.saveChanges() { self.tableView.reloadData() }
            }; done(true)
        }])
    }
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let vc = segue.destination as? ReceiptEditorViewController { vc.receipt = receipt }
        if let vc = segue.destination as? ItemEditorViewController { vc.receipt = receipt; vc.item = sender as? ReceiptItem }
        if let vc = segue.destination as? PeopleViewController { vc.receipt = receipt }
        if let vc = segue.destination as? SettlementViewController { vc.receipt = receipt }
        if let vc = segue.destination as? OCRReviewViewController { vc.receipt = receipt; vc.draft = sender as? OCRDraft }
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
            self.loadReceiptPhoto(provider) { [weak self] draft in self?.performSegue(withIdentifier: "reviewOCR", sender: draft) }
        }
    }
    func recognize(_ images: [UIImage]) {
        let progress = UIAlertController(title: "Reading receipt on device…", message: nil, preferredStyle: .alert)
        present(progress, animated: true)
        Task { @MainActor in
            do { let draft = try await ReceiptOCR.recognize(images); progress.dismiss(animated: true) { self.performSegue(withIdentifier: "reviewOCR", sender: draft) } }
            catch { progress.dismiss(animated: true) { self.showError(error.localizedDescription) } }
        }
    }
}
