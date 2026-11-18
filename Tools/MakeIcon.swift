import AppKit
@main struct MakeIcon {
    static func main() throws {
        let image = LogoArtwork.image(size: 1024)
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
