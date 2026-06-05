import AppKit

/// The post-detail overflow ("···") and share menus. Both borrow native macOS
/// context-menu manners — sectioned items, right-aligned ⌘ hints, destructive
/// actions in red — rendered on the elevated popover surface. Ported from
/// design/project/app/postmenus.jsx.

/// A single menu row: icon + label, optional sub-label and ⌘ shortcut hint.
func makeMenuRow(icon: String, label: String, sub: String? = nil, kbd: String? = nil,
                 danger: Bool = false, width: CGFloat, onClick: @escaping () -> Void) -> HoverControl {
    let theme = ThemeManager.shared.theme
    let height: CGFloat = sub == nil ? 38 : 46
    let row = HoverControl(frame: NSRect(x: 0, y: 0, width: width, height: height))
    row.wantsLayer = true
    row.layer?.cornerRadius = 8
    let tint = danger ? theme.negative : theme.fgBody
    let iconColor = danger ? theme.negative : theme.fgSubdued

    let glyph = GlyphView(name: icon, size: 19, color: iconColor)
    glyph.frame = NSRect(x: 11, y: (height - 19) / 2, width: 19, height: 19)
    row.addSubview(glyph)

    let textX: CGFloat = 11 + 19 + 12
    var kbdW: CGFloat = 0
    if let kbd {
        let k = makeLabel(kbd, font: Fonts.sans(12.5, .semibold), color: theme.fgDisabled, align: .right)
        kbdW = k.intrinsicContentSize.width
        k.frame = NSRect(x: width - 11 - kbdW, y: (height - k.intrinsicContentSize.height) / 2, width: kbdW, height: k.intrinsicContentSize.height)
        row.addSubview(k)
    }
    let labelW = width - textX - 11 - (kbdW > 0 ? kbdW + 10 : 0)
    if let sub {
        let l = makeLabel(label, font: Fonts.sans(14, .semibold), color: tint)
        l.lineBreakMode = .byTruncatingTail
        l.frame = NSRect(x: textX, y: 6, width: labelW, height: 18)
        row.addSubview(l)
        let s = makeLabel(sub, font: Fonts.sans(12, .medium), color: theme.fgSubdued)
        s.frame = NSRect(x: textX, y: 25, width: labelW, height: 15)
        row.addSubview(s)
    } else {
        let l = makeLabel(label, font: Fonts.sans(14, .semibold), color: tint)
        l.lineBreakMode = .byTruncatingTail
        l.frame = NSRect(x: textX, y: (height - l.intrinsicContentSize.height) / 2, width: labelW, height: l.intrinsicContentSize.height)
        row.addSubview(l)
    }

    let hoverBg = danger ? theme.negative.withAlphaComponent(0.13) : theme.gray100
    row.onState = { h, _ in row.layer?.backgroundColor = (h ? hoverBg : NSColor.clear).cgColor }
    row.onClick = onClick
    return row
}

/// A 1px divider with the design's 5px/8px insets.
func makeMenuSeparator(width: CGFloat) -> NSView {
    let theme = ThemeManager.shared.theme
    let v = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: 11))
    let line = NSView(frame: NSRect(x: 8, y: 5, width: width - 16, height: 1))
    line.wantsLayer = true
    line.layer?.backgroundColor = theme.borderDefault.cgColor
    v.addSubview(line)
    return v
}

/// Assemble an elevated menu surface from rows/separators and present it.
private func presentMenu(rows: [NSView], width: CGFloat, anchor: NSView, edge: PopoverEdge) {
    let theme = ThemeManager.shared.theme
    let content = FlippedView()
    content.wantsLayer = true
    content.layer?.backgroundColor = theme.bgElevated.cgColor
    content.layer?.cornerRadius = 13
    content.layer?.borderColor = theme.borderDefault.cgColor
    content.layer?.borderWidth = 1
    var y: CGFloat = 6
    for row in rows {
        row.frame.origin = CGPoint(x: 6, y: y)
        content.addSubview(row)
        y += row.frame.height
    }
    y += 6
    content.frame = NSRect(x: 0, y: 0, width: width, height: y)
    // Right-align the menu under/over its anchor (design: right: -4).
    let dx = anchor.bounds.width + 4 - width
    gPopoverHost?.presentPopover(content, width: width, height: y, anchor: anchor, edge: edge, dx: dx, dy: 0)
}

/// The ··· overflow menu shown on a post-detail header.
func presentMoreMenu(post: Post, anchor: NSView, callbacks: PostCallbacks) {
    let isX = post.author.platform == .x
    let a = post.author
    let at = isX ? "@\(a.handle)" : a.name
    let canonical = isX ? "https://x.com/\(a.handle)/status/\(post.id)" : "https://weibo.com/\(a.handle)"
    let w: CGFloat = 252
    let rowW = w - 12
    var rows: [NSView] = []

    let following = callbacks.isFollowing(a)
    rows.append(makeMenuRow(icon: following ? "block" : "user",
                            label: following ? (isX ? "Unfollow \(at)" : "取消关注 \(at)") : (isX ? "Follow \(at)" : "关注 \(at)"),
                            width: rowW) {
        gPopoverHost?.dismissPopover()
        callbacks.onFollow(a, !following)
        callbacks.onToast(following ? (isX ? "Unfollowed \(at)" : "已取消关注") : (isX ? "Following \(at)" : "已关注"))
    })
    rows.append(makeMenuRow(icon: "list", label: isX ? "Add/remove from Lists" : "从列表中添加/移除", width: rowW) {
        gPopoverHost?.dismissPopover(); callbacks.onAddToLists(post, anchor)
    })
    rows.append(makeMenuSeparator(width: rowW))
    rows.append(makeMenuRow(icon: "mute-chat", label: isX ? "Mute this conversation" : "隐藏此对话", width: rowW) {
        gPopoverHost?.dismissPopover(); callbacks.onMuteConversation(post)
    })
    let muted = callbacks.isMuted(a)
    rows.append(makeMenuRow(icon: "mute", label: muted ? (isX ? "Unmute \(at)" : "取消隐藏 \(at)") : (isX ? "Mute \(at)" : "隐藏 \(at)"), width: rowW) {
        gPopoverHost?.dismissPopover()
        callbacks.onMute(a, !muted)
        callbacks.onToast(muted ? (isX ? "Unmuted \(at)" : "已取消隐藏") : (isX ? "Muted \(at)" : "已隐藏 \(at)"))
    })
    let blocked = callbacks.isBlocked(a)
    rows.append(makeMenuRow(icon: "block", label: blocked ? (isX ? "Unblock \(at)" : "取消屏蔽 \(at)") : (isX ? "Block \(at)" : "屏蔽 \(at)"), danger: true, width: rowW) {
        gPopoverHost?.dismissPopover()
        callbacks.onBlock(a, !blocked)
        callbacks.onToast(blocked ? (isX ? "Unblocked \(at)" : "已取消屏蔽") : (isX ? "Blocked \(at)" : "已屏蔽 \(at)"))
    })
    rows.append(makeMenuSeparator(width: rowW))
    rows.append(makeMenuRow(icon: "newwindow", label: isX ? "Open in new window" : "在新窗口打开", kbd: "⌘⏎", width: rowW) {
        gPopoverHost?.dismissPopover(); callbacks.onOpenURL(canonical)
    })
    rows.append(makeMenuRow(icon: "poll", label: isX ? "View post analytics" : "查看帖子动态", width: rowW) {
        gPopoverHost?.dismissPopover(); callbacks.onOpenURL(canonical + "/analytics")
    })
    rows.append(makeMenuRow(icon: "code", label: isX ? "Embed post" : "嵌入帖子", width: rowW) {
        gPopoverHost?.dismissPopover(); callbacks.onEmbed(post)
    })
    rows.append(makeMenuSeparator(width: rowW))
    rows.append(makeMenuRow(icon: "flag", label: isX ? "Report post" : "举报帖子", danger: true, width: rowW) {
        gPopoverHost?.dismissPopover(); callbacks.onOpenURL(canonical + "/report")
    })

    presentMenu(rows: rows, width: w, anchor: anchor, edge: .below)
}

/// The share menu shown over the share action button.
func presentShareMenu(post: Post, anchor: NSView, callbacks: PostCallbacks) {
    let isX = post.author.platform == .x
    let hasMedia = post.media != nil
    let w: CGFloat = 248
    let rowW = w - 12
    var rows: [NSView] = []

    rows.append(makeMenuRow(icon: "message", label: isX ? "Send via Direct Message" : "通过私信发送", width: rowW) {
        gPopoverHost?.dismissPopover(); callbacks.onToast(isX ? "Opening message…" : "正在打开私信…")
    })
    rows.append(makeMenuRow(icon: "link", label: isX ? "Copy link" : "复制链接", kbd: "⌘C", width: rowW) {
        gPopoverHost?.dismissPopover(); callbacks.onCopyLink(post)
    })
    rows.append(makeMenuRow(icon: "share", label: isX ? "Share via…" : "帖子分享途径…",
                            sub: isX ? "AirDrop, Mail, and more" : "隔空投送、邮件等", width: rowW) {
        gPopoverHost?.dismissPopover()
    })
    if hasMedia {
        rows.append(makeMenuRow(icon: "download", label: isX ? "Save media" : "存储媒体", width: rowW) {
            gPopoverHost?.dismissPopover(); callbacks.onToast(isX ? "Saved to Downloads" : "已存储到下载")
        })
    }
    rows.append(makeMenuSeparator(width: rowW))
    let bookmarked = post.bookmarked
    rows.append(makeMenuRow(icon: "folder",
                            label: bookmarked ? (isX ? "Remove bookmark" : "取消收藏") : (isX ? "Bookmark to folder" : "收藏到文件夹"),
                            kbd: "⌘D", width: rowW) {
        gPopoverHost?.dismissPopover()
        callbacks.onAction(post.id, "bookmarked")
        callbacks.onToast(bookmarked ? (isX ? "Removed" : "已取消收藏") : (isX ? "Bookmarked" : "已收藏"))
    })

    presentMenu(rows: rows, width: w, anchor: anchor, edge: .above)
}
