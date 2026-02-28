import Foundation

extension [String: JSONValue] {
    var equipmentSummaryText: String {
        if case let .array(values)? = self["equipment"] {
            let equipment = values.compactMap { value -> String? in
                if case let .string(text) = value {
                    return text
                }
                return nil
            }
            if !equipment.isEmpty {
                return equipment.joined(separator: ", ")
            }
        }

        if case let .string(value)? = self["equipment"] {
            return value
        }

        return "Оборудование не указано"
    }
}

extension ProgramVersionSummary {
    var levelTitle: String {
        level?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? level! : "Базовый"
    }

    var frequencyTitle: String {
        if let frequencyPerWeek {
            return "\(frequencyPerWeek) дн/нед"
        }
        return "Частота не указана"
    }

    var equipmentTitle: String {
        requirements?.equipmentSummaryText ?? "Оборудование не указано"
    }
}
