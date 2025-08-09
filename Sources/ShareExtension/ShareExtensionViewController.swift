import Cocoa

class ShareExtensionViewController: NSViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        handleItems()
    }
    func handleItems() {
        guard let inputItems = self.extensionContext?.inputItems as? [NSExtensionItem] else { return }
        let providers = inputItems.flatMap { $0.attachments ?? [] }
        let group = DispatchGroup()
        for p in providers {
            if p.hasItemConformingToTypeIdentifier("public.file-url") {
                group.enter()
                p.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (item, error) in
                    defer { group.leave() }
                    if let url = item as? URL {
                        let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                        if let b64 = bookmark?.base64EncodedString() {
                            let s = "mistralocr://process?bookmark=" + b64
                            if let u = URL(string: s) { NSWorkspace.shared.open(u) }
                        }
                    }
                }
            }
        }
        group.notify(queue: .main) { self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil) }
    }
}
