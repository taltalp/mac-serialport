import AppKit
import SwiftUI

struct TerminalTextView: NSViewRepresentable {
    let content: NSAttributedString
    let autoScroll: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 14, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let contentChanged = !textView.attributedString().isEqual(to: content)
        if contentChanged {
            textView.textStorage?.setAttributedString(content)
        }

        let autoScrollBecameEnabled = autoScroll && !context.coordinator.wasAutoScrollEnabled
        context.coordinator.wasAutoScrollEnabled = autoScroll

        if autoScroll, contentChanged || autoScrollBecameEnabled {
            context.coordinator.scheduleScrollToBottom(
                scrollView: scrollView,
                textView: textView
            )
        } else if !autoScroll {
            context.coordinator.cancelPendingScroll()
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.cancelPendingScroll()
    }

    @MainActor
    final class Coordinator {
        var wasAutoScrollEnabled = false
        private var pendingScrollTask: Task<Void, Never>?

        func scheduleScrollToBottom(scrollView: NSScrollView, textView: NSTextView) {
            pendingScrollTask?.cancel()
            pendingScrollTask = Task { @MainActor [weak scrollView, weak textView] in
                await Task.yield()
                guard
                    !Task.isCancelled,
                    let scrollView,
                    let textView,
                    let textContainer = textView.textContainer,
                    let layoutManager = textView.layoutManager
                else { return }

                layoutManager.ensureLayout(for: textContainer)

                let usedRect = layoutManager.usedRect(for: textContainer)
                let horizontalInset = textView.textContainerInset.width * 2
                let verticalInset = textView.textContainerInset.height * 2
                textView.setFrameSize(NSSize(
                    width: max(scrollView.contentSize.width, ceil(usedRect.maxX + horizontalInset)),
                    height: max(scrollView.contentSize.height, ceil(usedRect.maxY + verticalInset))
                ))
                scrollView.layoutSubtreeIfNeeded()

                let clipView = scrollView.contentView
                let bottomY = max(0, textView.frame.height - clipView.bounds.height)
                clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: bottomY))
                scrollView.reflectScrolledClipView(clipView)
            }
        }

        func cancelPendingScroll() {
            pendingScrollTask?.cancel()
            pendingScrollTask = nil
        }
    }
}
