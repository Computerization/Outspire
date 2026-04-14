import AppIntents
import WidgetKit

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource {
        "Configuration"
    }

    static var description: IntentDescription {
        "Configure Outspire widget."
    }
}
