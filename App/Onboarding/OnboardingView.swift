import ComposableArchitecture
import SwiftUI
import UIKit

struct OnboardingView: View {
    let store: StoreOf<OnboardingFeature>
    @State private var athleteDisplayNameDraft = ""
    @State private var isNameFieldFocused = false

    var body: some View {
        VStack(spacing: FFSpacing.md) {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    Text("Создание профиля атлета")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)
                    Text("Проверьте имя профиля и продолжайте к тренировкам.")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }

            OnboardingNameField(
                label: "Имя профиля",
                placeholder: "Например: Алекс",
                text: $athleteDisplayNameDraft,
                helperText: "Имя можно изменить позже",
                isFocused: $isNameFieldFocused,
            )

            FFButton(
                title: store.isSubmitting ? "Создаём профиль..." : "Создать профиль",
                variant: store.isSubmitting ? .disabled : .primary,
            ) {
                isNameFieldFocused = false
                store.send(.createAthleteTapped(athleteDisplayNameDraft))
            }

            if let error = store.errorMessage {
                FFErrorState(
                    title: "Не удалось создать профиль",
                    message: error,
                    retryTitle: "Скрыть",
                ) {
                    store.send(.clearMessage)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, FFSpacing.md)
        .padding(.top, FFSpacing.lg)
        .onAppear {
            if athleteDisplayNameDraft != store.athleteDisplayName {
                athleteDisplayNameDraft = store.athleteDisplayName
            }
        }
    }
}

private struct OnboardingNameField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var helperText: String?
    @Binding var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpacing.xs) {
            Text(label)
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.textSecondary)

            OnboardingNativeTextField(
                text: $text,
                placeholder: placeholder,
                isFocused: $isFocused,
            )
            .frame(height: 52)
            .padding(.horizontal, FFSpacing.md)
            .background(FFColors.surface)
            .overlay {
                RoundedRectangle(cornerRadius: FFTheme.Radius.control, style: .continuous)
                    .stroke(isFocused ? FFColors.accent : FFColors.gray300, lineWidth: isFocused ? 2 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control, style: .continuous))

            if let helperText {
                Text(helperText)
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct OnboardingNativeTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange(_:)),
            for: .editingChanged,
        )
        textField.placeholder = placeholder
        textField.font = UIFont.preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.textColor = UIColor(FFColors.textPrimary)
        textField.tintColor = UIColor(FFColors.textPrimary)
        textField.autocapitalizationType = .words
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartDashesType = .no
        textField.smartQuotesType = .no
        textField.smartInsertDeleteType = .no
        textField.textContentType = nil
        textField.returnKeyType = .done
        textField.enablesReturnKeyAutomatically = false
        textField.clearButtonMode = .never
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.inputAssistantItem.leadingBarButtonGroups = []
        textField.inputAssistantItem.trailingBarButtonGroups = []
        if #available(iOS 17.0, *) {
            textField.inlinePredictionType = .no
        }
        if #available(iOS 18.0, *) {
            textField.writingToolsBehavior = .none
        }
        return textField
    }

    func updateUIView(_ uiView: UITextField, context _: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        if isFocused, uiView.window != nil, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFocused, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String
        @Binding private var isFocused: Bool

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            _text = text
            _isFocused = isFocused
        }

        @objc
        func textDidChange(_ textField: UITextField) {
            text = textField.text ?? ""
        }

        func textFieldDidBeginEditing(_: UITextField) {
            isFocused = true
        }

        func textFieldDidEndEditing(_: UITextField) {
            isFocused = false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return false
        }
    }
}
