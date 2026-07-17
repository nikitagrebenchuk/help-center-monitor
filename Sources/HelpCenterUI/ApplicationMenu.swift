import AppKit

public enum HelpCenterApplicationMenu {
    public static func make() -> NSMenu {
        let mainMenu = NSMenu()

        let applicationMenuItem = NSMenuItem(title: "Help Center Monitor", action: nil, keyEquivalent: "")
        let applicationMenu = NSMenu(title: "Help Center Monitor")
        applicationMenu.addItem(
            withTitle: "Close Help Center Monitor",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        applicationMenuItem.submenu = applicationMenu
        mainMenu.addItem(applicationMenuItem)

        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(makeEditItem(title: "Cut", action: #selector(NSText.cut(_:)), key: "x"))
        editMenu.addItem(makeEditItem(title: "Copy", action: #selector(NSText.copy(_:)), key: "c"))
        editMenu.addItem(makeEditItem(title: "Paste", action: #selector(NSText.paste(_:)), key: "v"))
        editMenu.addItem(.separator())
        editMenu.addItem(
            makeEditItem(title: "Select All", action: #selector(NSText.selectAll(_:)), key: "a")
        )
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        return mainMenu
    }

    private static func makeEditItem(title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = [.command]
        // A nil target sends the command to the active field editor. This is
        // essential for NSSecureTextField selection/cursor behavior.
        item.target = nil
        return item
    }
}
