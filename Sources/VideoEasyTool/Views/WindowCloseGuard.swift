import AppKit
import SwiftUI

struct WindowCloseGuard: NSViewRepresentable {
    @ObservedObject var viewModel: AppViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.attach(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.viewModel = viewModel
        DispatchQueue.main.async {
            context.coordinator.attach(to: nsView.window)
        }
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        weak var window: NSWindow?
        var viewModel: AppViewModel

        init(viewModel: AppViewModel) {
            self.viewModel = viewModel
        }

        func attach(to window: NSWindow?) {
            guard let window else { return }
            if self.window !== window {
                self.window = window
                window.delegate = self
            }
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard viewModel.isRunning else { return true }

            let alert = NSAlert()
            alert.messageText = "任务正在运行"
            alert.informativeText = "当前有任务还在执行。是否终止任务并退出应用？"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "终止并退出")
            alert.addButton(withTitle: "继续运行")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                viewModel.cancelCurrentTask()
                return true
            }
            return false
        }
    }
}
