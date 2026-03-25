import AppKit
import SwiftUI

struct LogTextView: NSViewRepresentable {
    let text: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        context.coordinator.scrollView = scrollView
        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        let shouldAutoScroll = context.coordinator.shouldAutoScroll
        textView.string = text
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)

        if shouldAutoScroll {
            DispatchQueue.main.async {
                context.coordinator.scrollToBottom()
            }
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    final class Coordinator: NSObject {
        weak var scrollView: NSScrollView?
        weak var textView: NSTextView?
        var shouldAutoScroll: Bool = true

        @objc
        func boundsDidChange(_ notification: Notification) {
            guard let scrollView else { return }
            shouldAutoScroll = isNearBottom(in: scrollView)
        }

        func isNearBottom(in scrollView: NSScrollView) -> Bool {
            guard let documentView = scrollView.documentView else { return true }
            let visibleMaxY = scrollView.contentView.bounds.maxY
            let contentHeight = documentView.frame.height
            return contentHeight - visibleMaxY < 24
        }

        func scrollToBottom() {
            guard let textView else { return }
            textView.scrollToEndOfDocument(nil)
            shouldAutoScroll = true
        }
    }
}
