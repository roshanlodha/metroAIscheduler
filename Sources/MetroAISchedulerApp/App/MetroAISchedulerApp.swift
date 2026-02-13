import SwiftUI
import AppKit

@main
struct MetroAISchedulerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 920, minHeight: 640)
        }
        .windowResizability(.automatic)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit MetroAIScheduler") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: [.command])
            }
        }

        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let hasCommand = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
            if hasCommand, event.charactersIgnoringModifiers?.lowercased() == "q" {
                NSApplication.shared.terminate(nil)
                return nil
            }
            return event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }
}
