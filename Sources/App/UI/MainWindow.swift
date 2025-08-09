import SwiftUI

struct MainWindow: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var showLeft: Bool = true
    @State private var showRight: Bool = true
    @State private var pending: [URL] = []
    
    var body: some View {
        HStack(spacing: 0) {
            if showLeft {
                HistoryView()
                    .frame(minWidth: 240, idealWidth: 280)
                    .overlay(alignment: .topTrailing) {
                        Button(action: { withAnimation { showLeft = false } }) {
                            Image(systemName: "sidebar.left")
                        }
                        .buttonStyle(.borderless)
                        .padding(6)
                    }
            }
            Divider()
            DropZoneView(pending: $pending)
                .frame(minWidth: 420, minHeight: 400)
            Divider()
            if showRight {
                SendPanel(pending: $pending)
                    .frame(minWidth: 260, idealWidth: 300)
                    .overlay(alignment: .topLeading) {
                        Button(action: { withAnimation { showRight = false } }) {
                            Image(systemName: "sidebar.right")
                        }
                        .buttonStyle(.borderless)
                        .padding(6)
                    }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                if !showLeft {
                    Button(action: { withAnimation { showLeft = true } }) {
                        Image(systemName: "sidebar.left")
                    }
                }
            }
            ToolbarItemGroup(placement: .automatic) {
                if !showRight {
                    Button(action: { withAnimation { showRight = true } }) {
                        Image(systemName: "sidebar.right")
                    }
                }
            }
        }
    }
}
