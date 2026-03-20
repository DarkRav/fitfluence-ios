import SwiftUI

enum WorkoutSetInputFormatting {
    static func normalizedWeightText(from rawValue: String) -> String? {
        guard let parsed = parseWeight(rawValue) else { return nil }
        return formatWeight(parsed)
    }

    static func normalizedRepsText(from rawValue: String) -> String? {
        guard let parsed = parseWholeNumber(rawValue) else { return nil }
        return String(parsed)
    }

    static func normalizedRPEText(from rawValue: String) -> String? {
        guard let parsed = parseWholeNumber(rawValue), (1 ... 10).contains(parsed) else {
            return nil
        }
        return String(parsed)
    }

    static func parseWeight(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let parsed = Double(normalized), parsed >= 0 else { return nil }
        return parsed
    }

    static func parseWholeNumber(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let parsed = Double(normalized), parsed >= 0 else { return nil }
        guard abs(parsed.rounded() - parsed) < 0.0001 else { return nil }
        return Int(parsed.rounded())
    }

    static func formatWeight(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return "\(Int(value))"
        }

        let multipliedByTen = value * 10
        if abs(multipliedByTen.rounded() - multipliedByTen) < 0.001 {
            return String(format: "%.1f", value)
        }

        return String(format: "%.2f", value)
    }

    static func formatStep(_ value: Double, suffix: String) -> String {
        "\(formatWeight(value)) \(suffix)"
    }
}

struct WorkoutSetRowView: View {
    let index: Int
    let set: SessionSetState
    let isBodyweight: Bool
    let showsCopyAction: Bool
    let weightStepLabel: String
    let isFocused: Bool
    let showsRPE: Bool
    let targetRPE: Int?
    let canRemove: Bool
    let onToggleComplete: () -> Void
    let onCopy: () -> Void
    let onToggleWarmup: () -> Void
    let onRemove: () -> Void
    let onWeightCommit: (String) -> Void
    let onDecreaseWeight: () -> Void
    let onIncreaseWeight: () -> Void
    let onRepsCommit: (String) -> Void
    let onDecreaseReps: () -> Void
    let onIncreaseReps: () -> Void
    let onSelectRPE: (Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpacing.sm) {
            HStack(spacing: FFSpacing.xs) {
                Button(action: onToggleComplete) {
                    Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(set.isCompleted ? FFColors.accent : FFColors.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Отметить подход \(index + 1) выполненным")

                Text("Подход \(index + 1)")
                    .font(FFTypography.body.weight(.semibold))
                    .foregroundStyle(FFColors.textPrimary)

                Spacer(minLength: FFSpacing.xs)

                if set.isCompleted {
                    completedSetBadge
                }

                if showsCopyAction {
                    Button("Копировать") {
                        onCopy()
                    }
                    .font(FFTypography.caption.weight(.semibold))
                    .foregroundStyle(FFColors.accent)
                    .frame(minHeight: 44)
                }
            }

            HStack(spacing: FFSpacing.sm) {
                if !isBodyweight {
                    WorkoutSetMetricInput(
                        title: "Вес",
                        valueText: set.weightText,
                        placeholder: "кг",
                        keyboardType: .decimalPad,
                        stepText: weightStepLabel,
                        kind: .weight,
                        onCommit: onWeightCommit,
                        onMinus: onDecreaseWeight,
                        onPlus: onIncreaseWeight,
                    )
                }

                WorkoutSetMetricInput(
                    title: "Повторы",
                    valueText: set.repsText,
                    placeholder: "повт",
                    keyboardType: .numberPad,
                    stepText: "1",
                    kind: .reps,
                    onCommit: onRepsCommit,
                    onMinus: onDecreaseReps,
                    onPlus: onIncreaseReps,
                )
            }

            if showsRPE {
                WorkoutSetRPEPicker(
                    selectedText: set.rpeText,
                    targetRPE: targetRPE,
                    onSelect: onSelectRPE,
                )
            }

            HStack(spacing: FFSpacing.xs) {
                Button(action: onToggleWarmup) {
                    Text(set.isWarmup ? "Разминочный подход" : "Отметить разминкой")
                        .font(FFTypography.caption.weight(.semibold))
                        .foregroundStyle(set.isWarmup ? FFColors.background : FFColors.textPrimary)
                        .padding(.horizontal, FFSpacing.sm)
                        .padding(.vertical, FFSpacing.xs)
                        .background(set.isWarmup ? FFColors.primary : FFColors.background.opacity(0.35))
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .stroke(set.isWarmup ? FFColors.primary : FFColors.gray700, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)

                Spacer(minLength: FFSpacing.xs)

                if canRemove {
                    Button("Удалить") {
                        onRemove()
                    }
                    .font(FFTypography.caption.weight(.semibold))
                    .foregroundStyle(FFColors.danger)
                    .padding(.horizontal, FFSpacing.sm)
                    .padding(.vertical, FFSpacing.xs)
                    .background(FFColors.danger.opacity(0.12))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(FFSpacing.sm)
        .background(FFColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                .stroke(isFocused ? FFColors.primary : FFColors.gray700, lineWidth: isFocused ? 1.6 : 1)
        }
    }

    private var completedSetBadge: some View {
        Text("Завершен")
            .font(FFTypography.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(FFColors.background)
            .padding(.horizontal, FFSpacing.sm)
            .padding(.vertical, FFSpacing.xs)
            .background(FFColors.primary)
            .clipShape(Capsule())
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct WorkoutSetMetricInput: View {
    enum Kind {
        case weight
        case reps
    }

    let title: String
    let valueText: String
    let placeholder: String
    let keyboardType: UIKeyboardType
    let stepText: String
    let kind: Kind
    let onCommit: (String) -> Void
    let onMinus: () -> Void
    let onPlus: () -> Void

    @FocusState private var isFocused: Bool
    @State private var draftText: String

    init(
        title: String,
        valueText: String,
        placeholder: String,
        keyboardType: UIKeyboardType,
        stepText: String,
        kind: Kind,
        onCommit: @escaping (String) -> Void,
        onMinus: @escaping () -> Void,
        onPlus: @escaping () -> Void,
    ) {
        self.title = title
        self.valueText = valueText
        self.placeholder = placeholder
        self.keyboardType = keyboardType
        self.stepText = stepText
        self.kind = kind
        self.onCommit = onCommit
        self.onMinus = onMinus
        self.onPlus = onPlus
        _draftText = State(initialValue: valueText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
            Text(title)
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.textSecondary)

            HStack(spacing: FFSpacing.xs) {
                stepControlButton(
                    systemName: "minus",
                    accessibilityLabel: "Уменьшить \(title.lowercased())",
                    action: onMinus,
                )

                ZStack {
                    RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                        .fill(FFColors.background.opacity(0.4))
                    RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                        .stroke(isFocused ? FFColors.primary : FFColors.gray700, lineWidth: isFocused ? 1.6 : 1)

                    if isFocused {
                        TextField(
                            "",
                            text: $draftText,
                            prompt: Text(placeholder).foregroundStyle(FFColors.gray500),
                        )
                        .keyboardType(keyboardType)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.center)
                        .font(FFTypography.body.weight(.semibold))
                        .foregroundStyle(FFColors.textPrimary)
                        .padding(.horizontal, FFSpacing.sm)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .focused($isFocused)
                    } else {
                        Button(action: beginEditing) {
                            Text(displayText)
                                .font(FFTypography.body.weight(.semibold))
                                .foregroundStyle(valueText.isEmpty ? FFColors.textSecondary : FFColors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Редактировать \(title.lowercased()) для подхода")
                    }
                }

                stepControlButton(
                    systemName: "plus",
                    accessibilityLabel: "Увеличить \(title.lowercased())",
                    action: onPlus,
                )
            }

            Text("Тап для ввода • шаг \(stepText)")
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: valueText) { _, newValue in
            if !isFocused {
                draftText = newValue
            }
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                draftText = valueText
            } else {
                commitDraft()
            }
        }
        .toolbar {
            if isFocused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") {
                        isFocused = false
                    }
                }
            }
        }
    }

    private var displayText: String {
        valueText.isEmpty ? placeholder : valueText
    }

    private func beginEditing() {
        draftText = valueText
        isFocused = true
    }

    private func commitDraft() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draftText = ""
            onCommit("")
            return
        }

        let normalized: String? = switch kind {
        case .weight:
            WorkoutSetInputFormatting.normalizedWeightText(from: draftText)
        case .reps:
            WorkoutSetInputFormatting.normalizedRepsText(from: draftText)
        }

        guard let normalized else {
            draftText = valueText
            return
        }

        draftText = normalized
        onCommit(normalized)
    }

    private func stepControlButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(FFColors.textPrimary)
                .frame(width: 44, height: 44)
                .background(FFColors.gray700)
                .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct WorkoutSetRPEPicker: View {
    let selectedText: String
    let targetRPE: Int?
    let onSelect: (Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
            HStack(spacing: FFSpacing.xs) {
                Text("Нагрузка")
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)

                if let targetRPE {
                    Text("цель \(targetRPE)")
                        .font(FFTypography.caption.weight(.semibold))
                        .foregroundStyle(FFColors.accent)
                        .padding(.horizontal, FFSpacing.xs)
                        .padding(.vertical, FFSpacing.xxs)
                        .background(FFColors.accent.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer(minLength: FFSpacing.xs)

                Text(selectedValue.map { "Текущее: \($0)" } ?? "Не указано")
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: FFSpacing.xs) {
                    ForEach(options, id: \.self) { value in
                        Button {
                            onSelect(selectedValue == value ? nil : value)
                        } label: {
                            Text("\(value)")
                                .font(FFTypography.caption.weight(.semibold))
                                .foregroundStyle(selectedValue == value ? FFColors.background : FFColors.textPrimary)
                                .padding(.horizontal, FFSpacing.sm)
                                .padding(.vertical, FFSpacing.xs)
                                .background(selectedValue == value ? FFColors.primary : FFColors.gray700)
                                .clipShape(Capsule())
                                .overlay {
                                    Capsule()
                                        .stroke(selectedValue == value ? FFColors.primary : FFColors.gray500, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Установить нагрузку \(value)")
                    }

                    if selectedValue != nil {
                        Button("Очистить") {
                            onSelect(nil)
                        }
                        .font(FFTypography.caption.weight(.semibold))
                        .foregroundStyle(FFColors.textSecondary)
                        .padding(.horizontal, FFSpacing.sm)
                        .padding(.vertical, FFSpacing.xs)
                        .background(FFColors.background.opacity(0.4))
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var selectedValue: Int? {
        WorkoutSetInputFormatting.parseWholeNumber(selectedText)
    }

    private var options: [Int] {
        var values = Set(6 ... 10)
        if let targetRPE, (1 ... 10).contains(targetRPE) {
            values.insert(targetRPE)
        }
        if let selectedValue, (1 ... 10).contains(selectedValue) {
            values.insert(selectedValue)
        }
        return values.sorted()
    }
}
