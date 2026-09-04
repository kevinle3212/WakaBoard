import SwiftUI
import Testing
@testable import WakaUI

/// Recomputes the palette's contrast claims from the palette's own numbers.
///
/// `scripts/validate_palette.js` checked these hues once, on 2026-08-29, against
/// Apple's light and dark surfaces. That run is evidence about a moment; this suite
/// is what stops the next hue edit from quietly invalidating it. Everything here is
/// arithmetic on published WCAG formulae — no rendering, no snapshot, no eye.
@Suite("Palette")
struct PaletteTests {
    private typealias RGB = WakaDesign.RGB
    private typealias Palette = WakaDesign.Palette

    /// The floor a chart mark must clear against its own surface.
    private let markFloor = 3.0

    @Test("the palette has eight hues in both modes, and they are different selections")
    func twoSelections() {
        #expect(Palette.categoricalLightRGB.count == 8)
        #expect(Palette.categoricalDarkRGB.count == 8)
        // If the dark palette were the light one reused, the dark surface would be
        // carrying hues chosen for white.
        #expect(Palette.categoricalLightRGB != Palette.categoricalDarkRGB)
    }

    @Test("every dark-mode hue clears 3:1 against the dark surface")
    func darkModeContrast() {
        for (index, hue) in Palette.categoricalDarkRGB.enumerated() {
            let ratio = hue.contrastRatio(against: Palette.darkSurface)
            #expect(ratio >= markFloor, "dark slot \(index) is \(ratio):1 against the dark surface")
        }
    }

    @Test("exactly the documented light-mode hues fall below 3:1, and no others")
    func lightModeReliefIsExactlyAsDocumented() {
        // The interesting assertion is the "no others": a future re-step that pushes a
        // fourth hue under the floor without updating the documented set fails here,
        // which is the only way the relief obligation stays honest.
        var below: Set<Int> = []
        for (index, hue) in Palette.categoricalLightRGB.enumerated()
        where hue.contrastRatio(against: Palette.lightSurface) < markFloor {
            below.insert(index)
        }
        #expect(below == Palette.lowContrastLightSlots)
    }

    @Test("the density ramp is monotone and never inverts")
    func densityRampIsMonotone() {
        // Light mode runs light to dark, so luminance must fall at every step; dark
        // mode runs the other way. A ramp that reverses anywhere reads as a higher
        // value at a lower one, which is the one thing a sequential scale must not do.
        let light = Palette.densityLightRGB.map(\.relativeLuminance)
        #expect(zip(light, light.dropFirst()).allSatisfy { $0 > $1 })
        let dark = Palette.densityDarkRGB.map(\.relativeLuminance)
        #expect(zip(dark, dark.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test("the density ramp's surface-adjacent end still reads as a mark")
    func densityRampEndsAreVisible() {
        // The step nearest the surface is the one that disappears into it. Two-to-one
        // is the ordinal floor: below it the palest cell is indistinguishable from an
        // empty one, and an empty cell here means "no coding", which is a different
        // claim entirely.
        #expect(Palette.densityLightRGB[0].contrastRatio(against: Palette.lightSurface) >= 2.0)
        #expect(Palette.densityDarkRGB[0].contrastRatio(against: Palette.darkSurface) >= 2.0)
    }

    @Test("the accent clears text contrast against its own surface")
    func accentContrast() {
        // The accent is used on links and buttons, so it carries text, and text needs
        // 4.5:1 rather than the 3:1 a chart mark needs.
        #expect(Palette.accentLightRGB.contrastRatio(against: Palette.lightSurface) >= 4.5)
        #expect(Palette.accentDarkRGB.contrastRatio(against: Palette.darkSurface) >= 4.5)
    }

    @Test("the series lookup never cycles a hue back onto the first slot")
    func seriesDoesNotCycle() {
        // A ninth series painted in the first hue asserts that it is the same thing as
        // the first series. Callers fold the tail before reaching here; this is the
        // backstop, and it must clamp rather than wrap.
        let first = Palette.series(0, scheme: .light)
        #expect(Palette.series(8, scheme: .light) != first)
        #expect(Palette.series(99, scheme: .light) == Palette.series(7, scheme: .light))
        #expect(Palette.series(-1, scheme: .light) == first)
    }

    @Test("zero density is never painted as the palest step by accident")
    func densityStepClampsSafely() {
        let ramp = Palette.density(.light)
        #expect(Palette.densityStep(for: 0, scheme: .light) == ramp.first)
        #expect(Palette.densityStep(for: 1, scheme: .light) == ramp.last)
        #expect(Palette.densityStep(for: 5, scheme: .light) == ramp.last)
        // A non-finite intensity must not index out of the ramp.
        #expect(Palette.densityStep(for: .nan, scheme: .light) == ramp.first)
    }

    @Test("the contrast formula agrees with the WCAG reference values")
    func formulaIsCorrect() {
        // Black on white is exactly 21:1, and any colour against itself is exactly
        // 1:1. Without these the suite above would happily certify a broken formula.
        let black = RGB(0, 0, 0)
        let white = RGB(1, 1, 1)
        #expect(abs(black.contrastRatio(against: white) - 21) < 0.001)
        #expect(abs(white.contrastRatio(against: white) - 1) < 0.001)
    }
}
