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

enum WorkoutExerciseDisplayFormatting {
    static func setLine(
        repsText: String?,
        weightText: String?,
        rpeText: String?,
        isBodyweight: Bool,
    ) -> String {
        let repsLabel = normalizedText(repsText) ?? "—"
        let rpeSuffix = normalizedText(rpeText).map { " • нагрузка \($0)" } ?? ""

        if isBodyweight {
            return "\(repsLabel) повт\(rpeSuffix)"
        }

        let weightLabel = normalizedText(weightText) ?? "—"
        return "\(repsLabel) повт • \(weightLabel) кг\(rpeSuffix)"
    }

    static func compactLastPerformanceLine(
        setCount: Int,
        repsValues: [Int],
        weightValues: [Double],
        isBodyweight: Bool,
    ) -> String? {
        guard setCount > 0 else { return nil }

        if isBodyweight {
            if let reps = repsValues.first,
               repsValues.count == setCount,
               repsValues.allSatisfy({ $0 == reps })
            {
                return "\(setCount)×\(reps)"
            }

            let reps = repsValues.first.map(String.init) ?? "—"
            return "\(setCount) подходов • \(reps) повторов"
        }

        if let reps = repsValues.first,
           repsValues.count == setCount,
           repsValues.allSatisfy({ $0 == reps }),
           let weight = weightValues.first,
           weightValues.count == setCount,
           weightValues.allSatisfy({ abs($0 - weight) < 0.01 })
        {
            return "\(setCount)×\(reps) @ \(WorkoutSetInputFormatting.formatWeight(weight)) кг"
        }

        let reps = repsValues.first.map(String.init) ?? "—"
        let weight = weightValues.first.map(WorkoutSetInputFormatting.formatWeight) ?? "—"
        return "\(setCount) подходов • \(reps) повторов @ \(weight) кг"
    }

    static func detailedLastPerformanceLine(
        reps: Int?,
        weight: Double?,
        isBodyweight: Bool,
    ) -> String? {
        if isBodyweight {
            guard let reps else { return nil }
            return "\(reps) повт"
        }

        guard let reps, let weight else { return nil }
        return "\(WorkoutSetInputFormatting.formatWeight(weight)) × \(reps)"
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
    let onSelect: () -> Void
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
        VStack(alignment: .leading, spacing: showsRPE ? FFSpacing.xs : 0) {
            HStack(spacing: FFSpacing.sm) {
                HStack(spacing: FFSpacing.xxs) {
                    Text("\(index + 1)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(isFocused ? FFColors.primary : FFColors.textSecondary)

                    if set.isWarmup {
                        Text("R")
                            .font(FFTypography.caption.weight(.bold))
                            .foregroundStyle(FFColors.primary)
                    }
                }
                .frame(width: 72, alignment: .leading)

                if !isBodyweight {
                    WorkoutSetMetricInput(
                        title: "Вес",
                        valueText: set.weightText,
                        placeholder: "—",
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
                    placeholder: "—",
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
        }
        .padding(.horizontal, FFSpacing.sm)
        .padding(.vertical, 10)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(rowBorder, lineWidth: isFocused ? 1.5 : 1)
        }
        .opacity(set.isCompleted ? 0.76 : 1)
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            if showsCopyAction {
                Button("Скопировать прошлый подход", systemImage: "doc.on.doc") {
                    onCopy()
                }
            }

            Button(set.isWarmup ? "Сделать рабочим" : "Отметить разминкой", systemImage: "flame") {
                onToggleWarmup()
            }

            if canRemove {
                Button("Удалить подход", systemImage: "trash", role: .destructive) {
                    onRemove()
                }
            }
        }
    }

    private var rowBackground: some ShapeStyle {
        if isFocused {
            return FFColors.surface.opacity(0.92)
        }
        return FFColors.surface.opacity(0.76)
    }

    private var rowBorder: Color {
        if isFocused {
            return FFColors.primary.opacity(0.65)
        }
        return FFColors.gray700.opacity(0.55)
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

    @State private var isEditing = false
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
        HStack(spacing: FFSpacing.xxs) {
            stepControlButton(
                systemName: "minus",
                accessibilityLabel: "Уменьшить \(title.lowercased())",
                action: onMinus,
            )

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(FFColors.background.opacity(0.36))
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isFocused ? FFColors.primary.opacity(0.6) : Color.clear, lineWidth: 1.5)

                if isEditing {
                    TextField(
                        "",
                        text: $draftText,
                        prompt: Text(placeholder).foregroundStyle(FFColors.gray500),
                    )
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.center)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(FFColors.textPrimary)
                    .tint(FFColors.textPrimary)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .focused($isFocused)
                    .onAppear {
                        DispatchQueue.main.async {
                            isFocused = true
                        }
                    }
                } else {
                    Button(action: beginEditing) {
                        Text(displayText)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(valueText.isEmpty ? FFColors.textSecondary : FFColors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .allowsTightening(true)
                            .frame(maxWidth: .infinity, minHeight: 60)
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
        .frame(maxWidth: .infinity)
        .onChange(of: valueText) { _, newValue in
            if !isFocused {
                draftText = newValue
            }
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                draftText = valueText
            } else {
                guard isEditing else { return }
                commitDraft()
                isEditing = false
            }
        }
    }

    private var displayText: String {
        valueText.isEmpty ? placeholder : valueText
    }

    private func beginEditing() {
        draftText = valueText
        isEditing = true
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
                .foregroundStyle(FFColors.textSecondary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct WorkoutSetRPEPicker: View {
    let selectedText: String
    let targetRPE: Int?
    let onSelect: (Int?) -> Void

    @State private var isInfoPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
            HStack(spacing: FFSpacing.xs) {
                Button {
                    isInfoPresented = true
                } label: {
                    HStack(spacing: 6) {
                        Text("Нагрузка (RPE)")
                            .font(FFTypography.caption)
                        Image(systemName: "info.circle")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(FFColors.textSecondary)
                }
                .buttonStyle(.plain)

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
        .alert("Субъективная нагрузка", isPresented: $isInfoPresented) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text("Оцените, насколько тяжёлым был подход по шкале от 1 до 10. 10 — максимум, 7–8 — осталось 2–3 повтора в запасе.")
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
