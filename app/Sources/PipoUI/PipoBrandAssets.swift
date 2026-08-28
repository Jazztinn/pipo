import AppKit

public enum PipoBrandAssets {
    public static let hollowLogo: NSImage = {
        guard let url = PipoResources.url(forResource: "PipoLogoHollow", withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else {
            return NSImage(systemSymbolName: "flag", accessibilityDescription: "Pipo") ?? NSImage()
        }
        image.accessibilityDescription = "Pipo"
        return image
    }()

    public static let hollowTemplateLogo: NSImage = {
        let image = adaptiveHollowLogo.copy() as? NSImage ?? adaptiveHollowLogo
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 19)
        return image
    }()

    public static let adaptiveHollowLogo: NSImage = {
        let image = hollowLogo.copy() as? NSImage ?? hollowLogo
        image.isTemplate = true
        image.accessibilityDescription = "Pipo"
        return image
    }()
}
