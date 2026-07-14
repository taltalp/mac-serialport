import AppKit
import SwiftUI

@main
struct SerialMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Serial Monitor") {
            ContentView(model: model)
                .frame(minWidth: 1_020, minHeight: 680)
                .onAppear {
                    appDelegate.model = model
                }
        }
        .defaultSize(width: 1_360, height: 820)
        .commands {
            CommandGroup(after: .newItem) {
                Button("新しい接続タブ") {
                    model.addSession()
                }
                .keyboardShortcut("t", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationWillTerminate(_ notification: Notification) {
        model?.closeAll()
    }
}

private struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Serial Monitor")
                .font(.title2.bold())
            Text("ポートごとの表示・通信設定は各タブに保存されます。")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 420, height: 140, alignment: .topLeading)
    }
}
