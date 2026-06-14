import Foundation

enum HomeDashboardDateRangeFormatter {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    static func weekRangeText(from start: Date, to end: Date) -> String {
        "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
}

enum HomeDashboardFormatting {
    static func plural(_ singular: String, count: Int) -> String {
        count == 1 ? singular : "\(singular)s"
    }

    static func cardCount(_ count: Int) -> String {
        count.formatted()
    }

    static func wordCount(_ value: Int) -> String {
        "\(value.formatted())"
    }

    static func countWithUnit(_ value: Int, singular: String, plural: String? = nil) -> String {
        "\(value.formatted()) \(value == 1 ? singular : (plural ?? "\(singular)s"))"
    }

    static func compactClock(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            }
            return "\(hours)h"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        if seconds > 0 {
            return "\(seconds)s"
        }
        return "0m"
    }

    static func savedMinutes(_ duration: TimeInterval) -> String {
        let minutes = Int((duration / 60).rounded())
        guard minutes > 0 else { return "0m" }
        return "\(minutes.formatted()) min"
    }

    static func savedTime(_ duration: TimeInterval) -> String {
        let minutes = max(0, Int((duration / 60).rounded()))
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 {
            return "\(hours) h"
        }
        return "\(hours)h \(remainder)m"
    }

    static func milestoneValue(_ value: Int, unit: String) -> String {
        if unit == "seconds" {
            return savedTime(TimeInterval(value))
        }
        let singularUnit: String
        switch unit {
        case "days":
            singularUnit = "day"
        case "sessions":
            singularUnit = "session"
        case "words":
            singularUnit = "word"
        default:
            singularUnit = unit
        }
        return countWithUnit(value, singular: singularUnit, plural: unit)
    }
}
