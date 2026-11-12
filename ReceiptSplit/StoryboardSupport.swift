import UIKit
import SwiftData

final class StoryboardInputCell: UITableViewCell {
    @IBOutlet weak var heading: UILabel!
    @IBOutlet weak var input: UITextField!
    var onChange: ((String) -> Void)?
    override func awakeFromNib() {
        super.awakeFromNib()
        input.addTarget(self, action: #selector(changed), for: .editingChanged)
    }
    @objc private func changed() { onChange?(input.text ?? "") }
}

final class StoryboardDisplayCell: UITableViewCell {
    @IBOutlet weak var heading: UILabel!
    @IBOutlet weak var detail: UILabel!
    @IBOutlet weak var icon: UIImageView!
}

// Every controller is instantiated from Main.storyboard. These helpers configure
// the storyboard's reusable table cells for dynamic, per-receipt data.
class StoryboardTableController: UITableViewController {
    var values: [String: String] = [:]
    override func viewDidLoad() { super.viewDidLoad(); tableView.keyboardDismissMode = .interactive }
    func cell(_ title: String, detail: String? = nil, accessory: UITableViewCell.AccessoryType = .none, id: String? = nil, symbol: String? = nil) -> StoryboardDisplayCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: symbol.map { "Symbol-" + $0 } ?? "Cell") as! StoryboardDisplayCell
        cell.contentView.subviews.filter { $0.tag == 977 }.forEach { $0.removeFromSuperview() }
        cell.heading.text = title; cell.detail.text = detail; cell.detail.isHidden = detail == nil
        cell.heading.numberOfLines = 1; cell.heading.lineBreakMode = .byTruncatingTail; cell.heading.font = .preferredFont(forTextStyle: .body); cell.detail.numberOfLines = 1
        cell.accessoryType = accessory; cell.selectionStyle = .default
        cell.icon.isHidden = symbol == nil
        cell.accessibilityIdentifier = id
        return cell
    }
    func field(_ key: String, placeholder: String, keyboard: UIKeyboardType = .default, id: String? = nil) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "InputCell") as! StoryboardInputCell
        cell.accessibilityIdentifier = nil
        cell.heading.text = key == "Name" ? placeholder : key
        let input = cell.input!
        input.placeholder = placeholder; input.text = values[key] ?? ""
        input.accessibilityIdentifier = id ?? key + "Field"
        input.accessibilityLabel = key
        input.keyboardType = keyboard
        cell.onChange = { [weak self] text in self?.values[key] = text; self?.inputChanged() }
        return cell
    }
    func inputChanged() {}
    func editorButtons(saveID: String) {
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        let save = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(savePressed))
        save.accessibilityIdentifier = saveID; navigationItem.rightBarButtonItem = save
    }
    @objc func cancel() { navigationController?.popViewController(animated: true) }
    @objc func savePressed() {}
    func popIfSaved() { if saveChanges() { navigationController?.popViewController(animated: true) } }
    func amount(_ key: String, signed: Bool = false) -> Int? { Money.parse(values[key] ?? "", signed: signed) }
}
