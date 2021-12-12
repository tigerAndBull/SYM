// The MIT License (MIT)
//
// Copyright (c) 2017 - present zqqf16
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Cocoa
import Combine

protocol DsymTableCellViewDelegate: AnyObject {
    func didClickSelectButton(_ cell: DsymTableCellView, sender: NSButton)
    func didClickRevealButton(_ cell: DsymTableCellView, sender: NSButton)
}

class DsymTableCellView: NSTableCellView {
    @IBOutlet weak var image: NSImageView!
    @IBOutlet weak var title: NSTextField!
    @IBOutlet weak var uuid: NSTextField!
    @IBOutlet weak var path: NSTextField!
    @IBOutlet weak var actionButton: NSButton!
    var deleteButton: NSButton!
    
    weak var delegate: DsymTableCellViewDelegate?
    
    var binary: Binary!
    var dsym: DsymFile?
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        deleteButton = NSButton.init(title: "删除", target: self, action: #selector(didClickDelete(_:)))
        deleteButton.font = NSFont.systemFont(ofSize: 10)
        self.addSubview(deleteButton)
    }
    
    override func layout() {
        self.deleteButton.frame = NSRect.init(x: self.actionButton.frame.origin.x + self.actionButton.frame.size.width + 12, y: self.actionButton.frame.origin.y, width: 55, height: 20)
    }
    
    func updateUI() {
        self.title.stringValue = self.binary.name
        self.uuid.stringValue = self.binary.uuid ?? ""
        if let path = self.dsym?.path {
            self.path.stringValue = path
            self.actionButton.title = NSLocalizedString("Reveal", comment: "Reveal in Finder")
            self.deleteButton.isHidden = false
            self.deleteButton.title = "删除"
        } else {
            self.path.stringValue = NSLocalizedString("dsym_file_not_found", comment: "Dsym file not found")
            self.actionButton.title = NSLocalizedString("Import", comment: "Import a dSYM file")
            self.deleteButton.isHidden = true
        }
    }
    
    @IBAction func didClickDelete(_ sender: Any) {
        self.dsym?.path = nil
        updateUI()
    }
    
    @IBAction func didClickActionButton(_ sender: NSButton) {
        if self.dsym?.path != nil {
            self.delegate?.didClickRevealButton(self, sender: sender)
        } else {
            self.delegate?.didClickSelectButton(self, sender: sender)
        }
    }
}

class DsymViewController: NSViewController {
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var tableViewHeight: NSLayoutConstraint!
    @IBOutlet weak var downloadButton: NSButton!
    @IBOutlet weak var progressBar: NSProgressIndicator!
    
    var importButton: NSButton!
    
    override func loadView() {
        super.loadView()
        importButton = NSButton.init(title: "一键导入", target: self, action: #selector(importAction))
        self.view.addSubview(importButton)
    }
    
    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    @objc func importAction() {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = false
        openPanel.canChooseFiles = true
        
        openPanel.begin { [weak openPanel] (result) in
            guard result == .OK, let url = openPanel?.url else {
                return
            }
            
            if (url.absoluteString.hasSuffix("dSYM")) {
                let element = url.absoluteString
                self.dsymManager?.binaries.forEach({ binary in
                    if element.hasSuffix("dSYM") {
                        if element.contains(binary.name) {
                            print("111", binary.name)
                            self.dsymFile(forBinary: binary)?.path = element
                        }
                    }
                })
                self.tableView.reloadData()
                return
            }
            
            var filePath = url.absoluteString
            if (filePath.hasPrefix("file://")) {
                filePath = filePath.substring(from: filePath.index(filePath.startIndex, offsetBy: 7))
            }
            let enumerator = FileManager.default.enumerator(atPath: filePath)
            while let element = enumerator?.nextObject() as? String {
                self.dsymManager?.binaries.forEach({ binary in
                    if element.hasSuffix("dSYM") {
                        if element.contains(binary.name) {
                            print(binary.name)
                            print(element)
                            let elementFilePath = filePath + element
                            print(elementFilePath)
                            self.dsymManager?.assign(binary, dsymFileURL: URL.init(fileURLWithPath: elementFilePath))
                        }
                    }
                })
            }
            self.tableView.reloadData()
        }
    }
    
    override func viewDidLayout() {
        self.importButton.frame = NSRect.init(x: self.downloadButton.frame.origin.x - 80 - 5, y: self.downloadButton.frame.origin.y + 5 , width: 80, height: 20)
    }
    
    private var binaries: [Binary] = [] {
        didSet {
            self.reloadData()
        }
    }
    
    private var dsymFiles: [String: DsymFile] = [:] {
        didSet {
            self.reloadData()
        }
    }
    
    private var dsymStorage = Set<AnyCancellable>()
    private var taskCancellable: AnyCancellable?

    var dsymManager: DsymManager? {
        didSet {
            self.dsymStorage.forEach { (cancellable) in
                cancellable.cancel()
            }
            dsymManager?.$binaries
                .receive(on: DispatchQueue.main)
                .assign(to: \.binaries, on: self)
                .store(in: &dsymStorage)
            
            dsymManager?.$dsymFiles
                .receive(on: DispatchQueue.main)
                .assign(to: \.dsymFiles, on: self)
                .store(in: &dsymStorage)
        }
    }

    private func reloadData() {
        guard self.tableView != nil else {
            return
        }
        
        self.tableView.reloadData()
        self.updateViewHeight()
    }
    
    private func dsymFile(forBinary binary: Binary) -> DsymFile? {
        if let uuid = binary.uuid {
            return self.dsymManager?.dsymFile(withUuid: uuid)
        }
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.updateViewHeight()
        self.downloadButton.isEnabled = self.dsymManager?.crash != nil
    }
    
    override func viewDidDisappear() {
        super.viewDidDisappear()
        self.taskCancellable?.cancel()
        self.dsymStorage.forEach { (cancellable) in
            cancellable.cancel()
        }
    }
    
    func bind(task: DsymDownloadTask?) {
        self.taskCancellable?.cancel()
        guard let downloadTask = task else {
            return
        }
        self.taskCancellable = Publishers
            .CombineLatest(downloadTask.$status, downloadTask.$progress)
            .receive(on: DispatchQueue.main)
            .sink { (status, progress) in
                self.update(status: status, progress: progress)
            }
    }

    //MARK: UI
    private func updateViewHeight() {
        self.tableViewHeight.constant = min(CGFloat(70 * self.binaries.count), 520.0)
    }
    
    @IBAction func didClickDownloadButton(_ sender: NSButton) {
        if let crashInfo = self.dsymManager?.crash {
            DsymDownloader.shared.download(crashInfo: crashInfo, fileURL: nil)
        }
    }
}

extension DsymViewController: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return self.binaries.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "cell"), owner: nil) as? DsymTableCellView
        cell?.delegate = self
        let binary = self.binaries[row]
        cell?.binary = binary
        cell?.dsym = self.dsymFile(forBinary: binary)
        cell?.updateUI()
        return cell
    }
    
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return false
    }
}

extension DsymViewController: DsymTableCellViewDelegate {
    func didClickSelectButton(_ cell: DsymTableCellView, sender: NSButton) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canCreateDirectories = false
        openPanel.canChooseFiles = true
        
        openPanel.begin { [weak openPanel] (result) in
            guard result == .OK, let url = openPanel?.url else {
                return
            }
            self.dsymManager?.assign(cell.binary!, dsymFileURL: url)
        }
    }

    func didClickRevealButton(_ cell: DsymTableCellView, sender: NSButton) {
        if let path = cell.dsym?.path {
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

extension DsymViewController {
    func update(status: DsymDownloadTask.Status, progress: DsymDownloadTask.Progress) {
        switch status {
        case .running:
            self.downloadButton.isEnabled = false
            self.progressBar.isHidden = false
        case .canceled:
            self.progressBar.isHidden = true
            self.downloadButton.isEnabled = true
        case .failed(_, _):
            self.progressBar.isHidden = true
            self.downloadButton.isEnabled = true
        case .success:
            self.progressBar.isHidden = true
        case .waiting:
            self.progressBar.isHidden = false
            self.progressBar.isIndeterminate = true
            self.progressBar.startAnimation(nil)
            self.downloadButton.isEnabled = false
        }
        if progress.percentage == 0 {
            self.progressBar.isIndeterminate = true
        } else {
            self.progressBar.isIndeterminate = false
            self.progressBar.doubleValue = Double(progress.percentage)
        }
    }
}
