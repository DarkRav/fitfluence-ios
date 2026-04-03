import SwiftUI

struct FFEmptyState: View {
    var title: String = "Пока пусто"
    var message: String = "Контент появится чуть позже"
    var fillsAvailableHeight = false

    var body: some View {
        FFCard {
            VStack(spacing: FFSpacing.sm) {
                Image(systemName: "tray")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(FFColors.gray300)
                Text(title)
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 180)
            .frame(maxHeight: fillsAvailableHeight ? .infinity : nil)
            .padding(.vertical, FFSpacing.md)
        }
        .frame(maxHeight: fillsAvailableHeight ? .infinity : nil)
    }
}

struct FFScreenStateLayout<Content: View, Footer: View>: View {
    private let content: Content
    private let footer: Footer
    private let spacing: CGFloat
    private let showsFooter: Bool

    init(
        spacing: CGFloat = FFSpacing.md,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.spacing = spacing
        self.content = content()
        self.footer = footer()
        self.showsFooter = Footer.self != EmptyView.self
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, FFSpacing.md)
            .padding(.top, FFSpacing.sm)
            .padding(.bottom, showsFooter ? FFSpacing.md : FFSpacing.lg)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showsFooter {
                    footer
                        .padding(.horizontal, FFSpacing.md)
                        .padding(.top, spacing)
                        .padding(.bottom, FFSpacing.md)
                        .background(FFColors.background)
                }
            }
    }
}

extension FFScreenStateLayout where Footer == EmptyView {
    init(
        spacing: CGFloat = FFSpacing.md,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            spacing: spacing,
            content: content,
            footer: { EmptyView() }
        )
    }
}

private struct FFVerticalReorderFramePreferenceKey: PreferenceKey {
    static var defaultValue: [AnyHashable: CGRect] = [:]

    static func reduce(value: inout [AnyHashable: CGRect], nextValue: () -> [AnyHashable: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct FFVerticalReorderStack<Item: Identifiable, RowContent: View>: View where Item.ID: Hashable {
    let items: [Item]
    let spacing: CGFloat
    let isEnabled: Bool
    let handleTouchSize: CGFloat
    let handleTopInset: CGFloat
    let handleTrailingInset: CGFloat
    let onReorder: (Item.ID, Item.ID) -> Void
    @ViewBuilder let rowContent: (Item, Bool) -> RowContent

    @State private var draggedID: AnyHashable?
    @State private var itemFrames: [AnyHashable: CGRect] = [:]
    @State private var dragCenterY: CGFloat = 0
    @State private var dragHeight: CGFloat = 0
    @State private var dragStartCenterY: CGFloat = 0

    private let coordinateSpaceName = "FFVerticalReorderStack"

    init(
        items: [Item],
        spacing: CGFloat = FFSpacing.md,
        isEnabled: Bool = true,
        handleTouchSize: CGFloat = 44,
        handleTopInset: CGFloat = 6,
        handleTrailingInset: CGFloat = 6,
        onReorder: @escaping (Item.ID, Item.ID) -> Void,
        @ViewBuilder rowContent: @escaping (Item, Bool) -> RowContent
    ) {
        self.items = items
        self.spacing = spacing
        self.isEnabled = isEnabled
        self.handleTouchSize = handleTouchSize
        self.handleTopInset = handleTopInset
        self.handleTrailingInset = handleTrailingInset
        self.onReorder = onReorder
        self.rowContent = rowContent
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: spacing) {
                ForEach(items) { item in
                    let itemKey = AnyHashable(item.id)
                    let isDragged = draggedID == itemKey

                    reorderRow(for: item, isDragged: isDragged)
                }
            }
            .coordinateSpace(name: coordinateSpaceName)

            if let draggedItem {
                rowContent(draggedItem, true)
                    .frame(width: draggedFrame?.width)
                    .offset(
                        x: draggedFrame?.minX ?? 0,
                        y: (dragCenterY - (dragHeight / 2))
                    )
                    .shadow(color: FFColors.background.opacity(0.14), radius: 14, y: 10)
                    .zIndex(10)
                    .allowsHitTesting(false)
            }
        }
        .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.9, blendDuration: 0.08), value: items.map(\.id))
        .onPreferenceChange(FFVerticalReorderFramePreferenceKey.self) { preferences in
            itemFrames = preferences
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled {
                draggedID = nil
                dragCenterY = 0
                dragHeight = 0
                dragStartCenterY = 0
            }
        }
    }

    private var draggedItem: Item? {
        guard let draggedID else { return nil }
        return items.first(where: { AnyHashable($0.id) == draggedID })
    }

    private var draggedFrame: CGRect? {
        guard let draggedID else { return nil }
        return itemFrames[draggedID]
    }

    @ViewBuilder
    private func reorderRow(for item: Item, isDragged: Bool) -> some View {
        let content = rowContent(item, false)
            .opacity(isDragged ? 0.08 : 1)
            .background(frameReader(for: item.id))
            .contentShape(Rectangle())

        if isEnabled {
            content.overlay(alignment: .topTrailing) {
                Color.clear
                    .frame(width: handleTouchSize, height: handleTouchSize)
                    .contentShape(Rectangle())
                    .padding(.top, handleTopInset)
                    .padding(.trailing, handleTrailingInset)
                    .simultaneousGesture(reorderGesture(for: item.id))
            }
        } else {
            content
        }
    }

    private func frameReader(for id: Item.ID) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: FFVerticalReorderFramePreferenceKey.self,
                value: [AnyHashable(id): proxy.frame(in: .named(coordinateSpaceName))]
            )
        }
    }

    private func reorderGesture(for id: Item.ID) -> some Gesture {
        LongPressGesture(minimumDuration: 0.12)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName)))
            .onChanged { value in
                switch value {
                case .first(true):
                    activateDragIfNeeded(for: id)
                case .second(true, let drag?):
                    activateDragIfNeeded(for: id)
                    updateDrag(for: id, with: drag.translation.height)
                default:
                    break
                }
            }
            .onEnded { _ in
                if draggedID == AnyHashable(id) {
                    draggedID = nil
                    dragStartCenterY = 0
                }
            }
    }

    private func activateDragIfNeeded(for id: Item.ID) {
        let key = AnyHashable(id)
        guard draggedID == nil, let frame = itemFrames[key] else { return }
        draggedID = key
        dragCenterY = frame.midY
        dragHeight = frame.height
        dragStartCenterY = frame.midY
    }

    private func updateDrag(for id: Item.ID, with translationY: CGFloat) {
        let key = AnyHashable(id)
        guard draggedID == key else { return }

        dragCenterY = dragStartCenterY + translationY
        maybeReorder(draggedID: id)
    }

    private func maybeReorder(draggedID: Item.ID) {
        let draggedKey = AnyHashable(draggedID)
        guard let currentIndex = items.firstIndex(where: { AnyHashable($0.id) == draggedKey }) else { return }

        if currentIndex < items.count - 1 {
            let nextItem = items[currentIndex + 1]
            let nextKey = AnyHashable(nextItem.id)
            if let nextFrame = itemFrames[nextKey], dragCenterY > nextFrame.midY {
                onReorder(draggedID, nextItem.id)
                return
            }
        }

        if currentIndex > 0 {
            let previousItem = items[currentIndex - 1]
            let previousKey = AnyHashable(previousItem.id)
            if let previousFrame = itemFrames[previousKey], dragCenterY < previousFrame.midY {
                onReorder(draggedID, previousItem.id)
            }
        }
    }
}
