import SwiftUI

/// The design tokens every WakaBoard view is built from.
///
/// One file, because a design system that lives in six view files is not a system.
/// Nothing below is decorative: a shipping view is not allowed to invent its own
/// spacing, radius, type step, or series colour, and `scripts/audit-checks.mjs
/// design` fails the build when one does. That check is the only thing that keeps
/// "uniform" true a month from now.
public enum WakaDesign {}

// MARK: - Spacing

public extension WakaDesign {
    /// The spacing scale. Every gap, inset, and stack spacing in the app is one of
    /// these six values.
    ///
    /// Six steps, not a continuum: the moment an arbitrary `14` is allowed, the
    /// rhythm between two screens stops matching and no reviewer can say why.
    enum Spacing {
        /// 4 pt — between a value and the label directly under it.
        public static let hairline: CGFloat = 4
        /// 8 pt — between related rows inside one card.
        public static let tight: CGFloat = 8
        /// 12 pt — between cards in a grid.
        public static let snug: CGFloat = 12
        /// 16 pt — the default inset of a card and of a screen edge.
        public static let regular: CGFloat = 16
        /// 24 pt — between sections of a screen.
        public static let loose: CGFloat = 24
        /// 32 pt — above and below a hero figure.
        public static let hero: CGFloat = 32
    }

    /// Corner radii, one per surface role.
    enum Radius {
        /// 8 pt — controls: fields, chips, small buttons.
        public static let control: CGFloat = 8
        /// 14 pt — cards and chart containers.
        public static let card: CGFloat = 14
        /// 22 pt — the hero surface at the top of the dashboard.
        public static let hero: CGFloat = 22
        /// 3 pt — the data end of a chart mark.
        ///
        /// Small on purpose. A fully rounded bar detaches from its own baseline, and
        /// a reader then judges the value from a curve rather than from a length.
        public static let mark: CGFloat = 3
        /// 2 pt — a legend swatch or any other square smaller than a control.
        public static let swatch: CGFloat = 2
    }

    /// Fixed heights for chart plot areas, so two charts on one screen line up.
    enum ChartHeight {
        /// A compact plot, used inside a card beside other content.
        public static let compact: CGFloat = 120
        /// The default plot height for a full-width chart.
        public static let regular: CGFloat = 180
        /// A tall plot, for the ranked comparison charts that carry many rows.
        public static let tall: CGFloat = 240
    }
}

// MARK: - Type

public extension Font {
    /// The dashboard's single largest number.
    ///
    /// Rounded and monospaced-digit: rounded because a duration is a friendly
    /// figure rather than a financial one, monospaced because the number changes
    /// every refresh and digits that shift width make it twitch. Sized from a
    /// semantic style, never a point size, so Dynamic Type still scales it.
    static let wakaHeroNumeral = Font.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit()

    /// The headline number on a metric card.
    static let wakaMetricNumeral = Font.system(.title2, design: .rounded).weight(.semibold).monospacedDigit()

    /// A number sitting inline in a list row or a chart label.
    static let wakaInlineNumeral = Font.system(.subheadline, design: .rounded).monospacedDigit()

    /// The title above a screen section.
    static let wakaSectionTitle = Font.headline

    /// The small title at the top of a card, above its value.
    static let wakaCardTitle = Font.subheadline.weight(.medium)

    /// Supporting prose: a caption, a footnote, a chart's text alternative.
    static let wakaCaption = Font.caption

    /// A file extension, a project identifier, or anything else the user reads as
    /// code rather than as prose.
    static let wakaCode = Font.system(.callout, design: .monospaced)
}

// MARK: - Colour

public extension WakaDesign {
    /// Every colour a chart or an accent is allowed to use.
    ///
    /// The categorical hues and their ordering are the validated reference palette
    /// from the `dataviz` skill, checked against Apple's own light (`#FFFFFF`) and
    /// dark (`#1C1C1E`) surfaces with `scripts/validate_palette.js` on 2026-08-29
    /// rather than chosen by eye. Both modes clear the lightness band, the chroma
    /// floor, adjacent colour-vision-deficiency separation, and the normal-vision
    /// floor. In light mode three hues — aqua, yellow, and magenta — fall below a
    /// 3:1 ratio against white, which the method permits only with relief: every
    /// WakaBoard chart therefore ships visible direct labels and a ranked list of
    /// the same figures, so identity is never carried by colour alone.
    ///
    /// The two modes are separate selections, not one palette lightened
    /// programmatically. A generated dark variant is what produces the muddy
    /// mid-greens that look fine in a preview and unreadable on a phone at night.
    /// One sRGB colour, kept as numbers rather than as a `Color`.
    ///
    /// A `Color` cannot be inspected portably, so a palette expressed only as
    /// `Color` values cannot be tested — and an untestable palette is one whose
    /// contrast claim rots the first time somebody nudges a hue. These are the
    /// numbers `scripts/validate_palette.js` was run against, and
    /// `Tests/WakaUITests/PaletteTests.swift` recomputes the same contrast from them.
    struct RGB: Hashable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(_ red: Double, _ green: Double, _ blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// This colour as SwiftUI sees it.
        public var color: Color { Color(red: red, green: green, blue: blue) }

        /// WCAG 2.2 relative luminance.
        public var relativeLuminance: Double {
            func channel(_ value: Double) -> Double {
                value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
        }

        /// The WCAG contrast ratio between this colour and `other`.
        public func contrastRatio(against other: RGB) -> Double {
            let a = relativeLuminance
            let b = other.relativeLuminance
            return (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }
    }

    enum Palette {
        /// The light chart surface these hues were validated against — `#FFFFFF`,
        /// which is what a SwiftUI card sits on in light appearance.
        public static let lightSurface = RGB(1, 1, 1)
        /// The dark chart surface — `#1C1C1E`, Apple's own dark system background.
        public static let darkSurface = RGB(0.110, 0.110, 0.118)

        /// Categorical hues in fixed order: blue, orange, aqua, yellow, magenta,
        /// green, violet, red.
        ///
        /// The order is the safety mechanism, not a preference — it is one of the
        /// orderings that clears every adjacent-pair gate in both modes. Series are
        /// assigned from slot 1 upward and the order is never cycled: a ninth series
        /// folds into "Other" rather than reusing slot 1, because a repeated hue
        /// asserts a relationship that does not exist.
        public static let categoricalLightRGB: [RGB] = [
            RGB(0.165, 0.471, 0.839), // #2a78d6 blue
            RGB(0.922, 0.408, 0.204), // #eb6834 orange
            RGB(0.106, 0.686, 0.478), // #1baf7a aqua
            RGB(0.929, 0.631, 0.000), // #eda100 yellow
            RGB(0.910, 0.482, 0.643), // #e87ba4 magenta
            RGB(0.000, 0.514, 0.000), // #008300 green
            RGB(0.290, 0.227, 0.655), // #4a3aa7 violet
            RGB(0.890, 0.286, 0.282)  // #e34948 red
        ]

        /// The same eight hues, re-stepped for a dark surface.
        ///
        /// A separate selection, not the light palette lightened programmatically. A
        /// generated dark variant is what produces the muddy mid-greens that look
        /// fine in a preview and unreadable on a phone at night.
        public static let categoricalDarkRGB: [RGB] = [
            RGB(0.224, 0.529, 0.898), // #3987e5 blue
            RGB(0.851, 0.349, 0.149), // #d95926 orange
            RGB(0.098, 0.620, 0.439), // #199e70 aqua
            RGB(0.788, 0.522, 0.000), // #c98500 yellow
            RGB(0.835, 0.318, 0.506), // #d55181 magenta
            RGB(0.000, 0.514, 0.000), // #008300 green
            RGB(0.565, 0.522, 0.914), // #9085e9 violet
            RGB(0.902, 0.404, 0.404)  // #e66767 red
        ]

        /// The single-hue indigo ramp used for density, lightest to darkest.
        ///
        /// Sequential encoding gets one hue, never a rainbow. Indigo because it is
        /// WakaBoard's own accent, so the ribbon reads as part of the app rather
        /// than as a borrowed chart.
        public static let densityLightRGB: [RGB] = [
            RGB(0.647, 0.639, 0.941), // #a5a3f0
            RGB(0.545, 0.522, 0.949), // #8b85f2
            RGB(0.435, 0.400, 0.918), // #6f66ea
            RGB(0.310, 0.275, 0.898), // #4f46e5
            RGB(0.227, 0.196, 0.678)  // #3a32ad
        ]

        /// The density ramp stepped for a dark surface, darkest to lightest.
        public static let densityDarkRGB: [RGB] = [
            RGB(0.290, 0.255, 0.710), // #4a41b5
            RGB(0.365, 0.329, 0.816), // #5d54d0
            RGB(0.447, 0.412, 0.925), // #7269ec
            RGB(0.565, 0.537, 0.949), // #9089f2
            RGB(0.702, 0.682, 0.976)  // #b3aef9
        ]

        /// WakaBoard's accent, taken from its own wordmark.
        public static let accentLightRGB = RGB(0.310, 0.275, 0.898) // #4f46e5
        /// The accent stepped for a dark surface.
        public static let accentDarkRGB = RGB(0.545, 0.522, 0.949) // #8b85f2

        /// The hues that fall below 3:1 against the light surface.
        ///
        /// Not a defect and not an oversight: the validated palette accepts them on
        /// the condition that the figures are also written down, which every chart
        /// here does. Named as slot indices so a future re-step has to update this
        /// list deliberately rather than let the relief obligation lapse in silence.
        public static let lowContrastLightSlots: Set<Int> = [2, 3, 4]

        /// The categorical hues for `scheme`.
        public static func categorical(_ scheme: ColorScheme) -> [Color] {
            (scheme == .dark ? categoricalDarkRGB : categoricalLightRGB).map(\.color)
        }

        /// The density ramp for `scheme`, ordered from the lowest value to the highest.
        public static func density(_ scheme: ColorScheme) -> [Color] {
            (scheme == .dark ? densityDarkRGB : densityLightRGB).map(\.color)
        }

        /// The accent for `scheme`.
        public static func accent(_ scheme: ColorScheme) -> Color {
            (scheme == .dark ? accentDarkRGB : accentLightRGB).color
        }

        /// The hue for the series at `index`, folding anything past the eighth slot
        /// onto the last slot rather than cycling back to the first.
        ///
        /// Cycling is what makes a ninth series look like the first one. Callers are
        /// expected to have folded the tail into a single "Other" series before
        /// reaching here; this is the backstop, not the plan.
        public static func series(_ index: Int, scheme: ColorScheme) -> Color {
            let hues = categorical(scheme)
            return hues[min(max(index, 0), hues.count - 1)]
        }

        /// The density step for `fraction`, a value in `0...1`.
        ///
        /// Zero is deliberately not the palest step: a day with no coding is absence,
        /// not a small amount, and painting it as the ramp's first colour would claim
        /// activity that did not happen. Callers render zero with the empty surface.
        public static func densityStep(for fraction: Double, scheme: ColorScheme) -> Color {
            let ramp = density(scheme)
            guard fraction.isFinite else { return ramp[0] }
            let clamped = min(max(fraction, 0), 1)
            let step = Int((clamped * Double(ramp.count - 1)).rounded())
            return ramp[min(step, ramp.count - 1)]
        }
    }
}

// MARK: - Surfaces

/// A card: the one container every grouped figure in WakaBoard sits in.
///
/// A modifier rather than a wrapper view, so it composes with `LazyVGrid` cells,
/// `Form` rows, and chart containers without adding a layout level to each.
public struct WakaCard: ViewModifier {
    /// Padding inside the card.
    let inset: CGFloat
    /// The card's corner radius.
    let radius: CGFloat

    public func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(inset)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: radius))
    }
}

public extension View {
    /// Places this content on a standard WakaBoard card surface.
    func wakaCard() -> some View {
        modifier(WakaCard(inset: WakaDesign.Spacing.regular, radius: WakaDesign.Radius.card))
    }

    /// Places this content on the taller, rounder hero surface used once per screen.
    func wakaHeroSurface() -> some View {
        modifier(WakaCard(inset: WakaDesign.Spacing.loose, radius: WakaDesign.Radius.hero))
    }
}
