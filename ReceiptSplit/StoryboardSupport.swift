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

// Every controller is instantiated from Main.storyboard. These helpers configure
// the storyboard's reusable table cells for dynamic, per-receipt data.
class StoryboardTableController: UITableViewController {
    var values: [String: String] = [:]
    override func viewDidLoad() { super.viewDidLoad(); tableView.keyboardDismissMode = .interactive }
    func cell(_ title: String, detail: String? = nil, accessory: UITableViewCell.AccessoryType = .none, id: String? = nil, symbol: String? = nil, tint: UIColor = .systemIndigo) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell")!
        cell.contentView.subviews.filter { $0.tag == 977 }.forEach { $0.removeFromSuperview() }
        cell.textLabel?.text = title; cell.detailTextLabel?.text = detail
        cell.textLabel?.numberOfLines = 1; cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.accessoryType = accessory; cell.selectionStyle = .default
        cell.imageView?.image = symbol.flatMap { UIImage(systemName: $0) }
        cell.imageView?.tintColor = tint
        cell.accessibilityIdentifier = id
        return cell
    }
    func stageHeader(_ title: String, subtitle: String, symbol: String, color: UIColor) {
        let header = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 116))
        header.autoresizingMask = [.flexibleWidth]
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = color; icon.contentMode = .scaleAspectFit
        let heading = UILabel(); heading.text = title; heading.font = .preferredFont(forTextStyle: .title2); heading.adjustsFontForContentSizeCategory = true; heading.numberOfLines = 1
        let caption = UILabel(); caption.text = subtitle; caption.font = .preferredFont(forTextStyle: .subheadline); caption.textColor = .secondaryLabel; caption.numberOfLines = 2; caption.adjustsFontForContentSizeCategory = true
        let stack = UIStackView(arrangedSubviews: [heading, caption]); stack.axis = .vertical; stack.spacing = 5
        for v in [icon, stack] { v.translatesAutoresizingMaskIntoConstraints = false; header.addSubview(v) }
        NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 22), icon.centerYAnchor.constraint(equalTo: header.centerYAnchor), icon.widthAnchor.constraint(equalToConstant: 42), icon.heightAnchor.constraint(equalToConstant: 42), stack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20), stack.centerYAnchor.constraint(equalTo: header.centerYAnchor)])
        tableView.tableHeaderView = header
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
