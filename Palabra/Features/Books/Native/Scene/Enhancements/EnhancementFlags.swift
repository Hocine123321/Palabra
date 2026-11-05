import Foundation

/// Which enhancement effects are on right now. Pure, so the gating rules can be tested without a renderer.
struct EnhancementFlags: Equatable {
    /// Soft contact shadows under books and props.
    var ao = false
    /// Gentle depth of field in the menu.
    var dof = false
    /// A warm glow around the lamp bulb and a pool of light (dark mode).
    var bloom = false
    /// Dust motes drifting through the light.
    var dust = false
    /// Things that settle by themselves: the ribbon and the camera's device-motion sway.
    var sway = false
    /// A very slow drift in the lamp's intensity (dark mode).
    var flicker = false
    /// A light tap when a leaf lands.
    var haptics = false

    static let off = EnhancementFlags()

    /// Battery saver removes every effect (as it already removes shadows); Reduce Motion removes what moves by itself; reading
    /// removes anything that could touch the text (depth of field, dust); a moved Free view removes depth of field too.
    static func resolve(enabled: Bool = true, quality: SceneQuality, reduceMotion: Bool, moved: Bool, reading: Bool, dark: Bool = false) -> EnhancementFlags {
        guard enabled else { return .off }
        var flags = EnhancementFlags()
        flags.haptics = true
        guard quality != .saver else { return flags }
        flags.ao = true
        flags.dof = !reading && !moved && !reduceMotion
        flags.bloom = dark
        flags.dust = !reading && !reduceMotion
        flags.sway = !reduceMotion
        flags.flicker = dark && !reduceMotion
        return flags
    }
}
