import UIKit

final class PeopleViewController: StoryboardTableController {
    var receipt: Receipt!
    override func viewDidLoad() { super.viewDidLoad(); title = "Participants"; navigationItem.largeTitleDisplayMode = .never; stageHeader("Who’s splitting?", subtitle: "Add everyone and record payments to the merchant.", symbol: "person.2.fill", color: .systemTeal) }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); tableView.reloadData() }
    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? receipt.people.count + 1 : 3 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { section == 0 ? "Participants" : "Payments" }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { section == 0 ? "Record what each person paid to the merchant. Removing a participant removes their item allocations." : nil }
    override func tableView(_ tableView: UITableView, cellForRowAt p: IndexPath) -> UITableViewCell {
        if p.section == 0 {
            if p.row == receipt.people.count { return cell("Add participant", accessory: .disclosureIndicator, id: "addPerson", symbol: "person.badge.plus", tint: .systemTeal) }
            let person = receipt.people[p.row]
            return cell(person.name, detail: "Paid \(Money.format(person.paid))", accessory: .disclosureIndicator, id: "person-" + person.name, symbol: "person.crop.circle.fill", tint: .systemTeal)
        }
        let paid = receipt.people.reduce(0) { $0 + $1.paid }
        let rows = [("Bill total", receipt.total), ("Recorded payments", paid), ("Remaining", receipt.total - paid)]
        return cell(rows[p.row].0, detail: Money.format(rows[p.row].1))
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt p: IndexPath) {
        tableView.deselectRow(at: p, animated: true)
        if p.section == 0 { performSegue(withIdentifier: "editPerson", sender: p.row < receipt.people.count ? receipt.people[p.row] : nil) }
    }
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) { if let vc = segue.destination as? PersonEditorViewController { vc.receipt = receipt; vc.person = sender as? Participant } }
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
        target.name = name; target.paid = paid; receipt.reviewed = false; popIfSaved()
    }
}
