import UIKit

enum SavedPeople {
    private static let key = "savedParticipantNames"
    static var names: [String] { names(in: .standard) }
    static func names(in defaults: UserDefaults) -> [String] { (defaults.stringArray(forKey: key) ?? []).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } }
    static func add(_ value: String, in defaults: UserDefaults = .standard) -> Bool {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = names(in: defaults)
        guard !name.isEmpty, !saved.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return false }
        defaults.set(saved + [name], forKey: key); return true
    }
    static func remove(_ name: String, in defaults: UserDefaults = .standard) { defaults.set(names(in: defaults).filter { $0 != name }, forKey: key) }
    static func resetForTesting() { UserDefaults.standard.removeObject(forKey: key) }
}

final class PeopleViewController: StoryboardTableController {
    var receipt: Receipt!
    override func viewDidLoad() { super.viewDidLoad(); title = "Participants"; navigationItem.largeTitleDisplayMode = .never }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); tableView.reloadData() }
    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? receipt.people.count + 2 : 3 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { section == 0 ? "Participants" : "Payments" }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { section == 0 ? "Record what each person paid to the merchant. Removing a participant removes their item allocations." : nil }
    override func tableView(_ tableView: UITableView, cellForRowAt p: IndexPath) -> UITableViewCell {
        if p.section == 0 {
            if p.row == receipt.people.count { return cell("Add participant", accessory: .disclosureIndicator, id: "addPerson", symbol: "person.badge.plus") }
            if p.row == receipt.people.count + 1 { return cell("Choose saved people", accessory: .disclosureIndicator, id: "savedPeopleLink", symbol: "person.crop.circle.fill") }
            let person = receipt.people[p.row]
            return cell(person.name, detail: "Paid \(Money.format(person.paid))", accessory: .disclosureIndicator, id: "person-" + person.name, symbol: "person.crop.circle.fill")
        }
        let paid = receipt.people.reduce(0) { $0 + $1.paid }
        let rows = [("Bill total", receipt.total), ("Recorded payments", paid), ("Remaining", receipt.total - paid)]
        return cell(rows[p.row].0, detail: Money.format(rows[p.row].1))
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt p: IndexPath) {
        tableView.deselectRow(at: p, animated: true)
        if p.section == 0 {
            if p.row == receipt.people.count + 1 { performSegue(withIdentifier: "showSavedPeople", sender: nil) }
            else { performSegue(withIdentifier: "editPerson", sender: p.row < receipt.people.count ? receipt.people[p.row] : nil) }
        }
    }
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let vc = segue.destination as? PersonEditorViewController { vc.receipt = receipt; vc.person = sender as? Participant }
        if let vc = segue.destination as? SavedPeopleViewController { vc.receipt = receipt }
    }
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt p: IndexPath) -> UISwipeActionsConfiguration? {
        guard p.section == 0, p.row < receipt.people.count else { return nil }
        let person = receipt.people[p.row]
        return UISwipeActionsConfiguration(actions: [UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            self?.confirm("Remove participant?", message: "Their allocations will also be removed.", actionTitle: "Remove") {
                guard let self else { return }; self.receipt.people.removeAll { $0.id == person.id }
                for item in self.receipt.items {
                    var allocations = item.allocations
                    if allocations.removeValue(forKey: person.id.uuidString) != nil {
                        if allocations.isEmpty { allocations["removed"] = 0 }; item.allocations = allocations
                    }
                }
                self.store.delete(person); self.receipt.reviewed = false
                if self.saveChanges() { self.tableView.reloadData() }
            }; done(true)
        }])
    }
}

final class PersonEditorViewController: StoryboardTableController {
    var receipt: Receipt!
    var person: Participant?
    override func viewDidLoad() {
        super.viewDidLoad(); title = person == nil ? "Add participant" : "Edit participant"; editorButtons(saveID: "savePerson")
        values = ["Name": person?.name ?? "", "Amount paid": Money.edit(person?.paid ?? 0)]; inputChanged()
    }
    override func inputChanged() { navigationItem.rightBarButtonItem?.isEnabled = !(values["Name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 2 }
    override func tableView(_ tableView: UITableView, cellForRowAt p: IndexPath) -> UITableViewCell {
        p.row == 0 ? field("Name", placeholder: "Name", id: "personNameField") : field("Amount paid", placeholder: "0.00", keyboard: .decimalPad)
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { "Amount paid is what this person paid to the merchant, before settling with the group." }
    override func savePressed() {
        let name = (values["Name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !receipt.people.contains(where: { $0.id != person?.id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { showError("Use a different name so each person is easy to identify."); return }
        guard let paid = amount("Amount paid") else { showError("Enter a valid payment amount."); return }
        let target = person ?? Participant(name: name)
        if person == nil { receipt.people.append(target) }
        target.name = name; target.paid = paid; receipt.reviewed = false
        if saveChanges() { if person == nil { _ = SavedPeople.add(name) }; navigationController?.popViewController(animated: true) }
    }
}

final class SavedPeopleViewController: StoryboardTableController {
    var receipt: Receipt?
    override func viewDidLoad() { super.viewDidLoad(); title = "Saved people"; navigationItem.largeTitleDisplayMode = .never }
    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 2 : max(SavedPeople.names.count, 1) }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { section == 0 ? "Add a person" : "Saved on this device" }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 { return "Saved names can be reused. Payments stay separate for each receipt." }
        return receipt == nil ? "Swipe left to remove a saved name. Existing receipts stay unchanged." : "Tap a name to add it to this receipt. Swipe left to remove a saved name."
    }
    override func tableView(_ tableView: UITableView, cellForRowAt p: IndexPath) -> UITableViewCell {
        if p.section == 0 { return p.row == 0 ? field("Name", placeholder: "Person’s name", id: "savedPersonName") : cell("Save person", id: "saveReusablePerson") }
        guard !SavedPeople.names.isEmpty else { return cell("No saved people yet") }
        let name = SavedPeople.names[p.row]
        let added = receipt?.people.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame } ?? false
        return cell(name, detail: added ? "Already on this receipt" : nil, accessory: added ? .checkmark : .none, id: "saved-" + name)
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt p: IndexPath) {
        tableView.deselectRow(at: p, animated: true)
        if p.section == 0 && p.row == 1 {
            guard SavedPeople.add(values["Name"] ?? "") else { showError("Enter a name that is not already saved."); return }
            values["Name"] = ""; view.endEditing(true); tableView.reloadData(); return
        }
        guard p.section == 1, let receipt, p.row < SavedPeople.names.count else { return }
        let name = SavedPeople.names[p.row]
        guard !receipt.people.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { showError("This person is already on the receipt."); return }
        receipt.people.append(Participant(name: name)); receipt.reviewed = false
        if saveChanges() { tableView.reloadData() }
    }
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt p: IndexPath) -> UISwipeActionsConfiguration? {
        guard p.section == 1, p.row < SavedPeople.names.count else { return nil }
        let name = SavedPeople.names[p.row]
        return UISwipeActionsConfiguration(actions: [UIContextualAction(style: .destructive, title: "Remove") { [weak self] _, _, done in
            self?.confirm("Remove saved person?", message: "Existing receipts will keep their participants.", actionTitle: "Remove") { SavedPeople.remove(name); self?.tableView.reloadData() }; done(true)
        }])
    }
}
