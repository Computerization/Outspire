import SwiftUI

/// Bold, confident text styles — not generic.
public enum AppText {
    // Hero: onboarding, empty states
    public static var heroTitle: Font {
        .largeTitle.weight(.bold)
    }

    /// Card headers — rounded for premium Countdown+ feel
    public static var cardTitle: Font {
        .title3.weight(.bold).leading(.tight)
    }

    /// Section labels
    public static var sectionTitle: Font {
        .headline.weight(.bold)
    }

    /// Card and section titles — bold, not just semibold (legacy alias)
    public static var title: Font {
        .title2.weight(.bold)
    }

    /// Card subtitles — slightly lighter than title
    public static var subtitle: Font {
        .title3.weight(.semibold)
    }

    /// Form labels, row titles
    public static var label: Font {
        .subheadline.weight(.medium)
    }

    /// Primary reading size
    public static var body: Font {
        .body
    }

    /// Emphasized body
    public static var bodyBold: Font {
        .body.weight(.semibold)
    }

    /// Countdown timers — monospaced digits
    public static var monoBody: Font {
        .body.weight(.bold).monospacedDigit()
    }

    /// Secondary/meta information
    public static var meta: Font {
        .footnote
    }

    /// Small captions
    public static var caption: Font {
        .caption
    }

    /// Tiny labels
    public static var micro: Font {
        .caption2
    }
}
