import MessageUI
import SwiftUI

struct HelpAndDiagnosticsView: View {
    @Bindable var viewModel: ProfileViewModel
    @Environment(\.openURL) private var openURL

    @State private var isMailComposerPresented = false
    @State private var isMailFallbackAlertPresented = false

    var body: some View {
        ScrollView {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.sm) {
                    Text("Помощь")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)

                    FFButton(title: "Сообщить о проблеме", variant: .secondary) {
                        if MFMailComposeViewController.canSendMail() {
                            isMailComposerPresented = true
                        } else {
                            isMailFallbackAlertPresented = true
                        }
                    }
                    .accessibilityLabel("Сообщить о проблеме")

                    FFButton(title: "Скопировать диагностику", variant: .secondary) {
                        UIPasteboard.general.string = viewModel.diagnosticsText
                        viewModel.infoMessage = "Диагностика скопирована"
                    }
                    .accessibilityLabel("Скопировать диагностику")

                    FFButton(title: "Повторить синхронизацию", variant: .secondary) {
                        Task { await viewModel.retrySyncNow() }
                    }
                    .accessibilityLabel("Повторить синхронизацию")

                    FFButton(title: "Скопировать журнал синхронизации", variant: .secondary) {
                        Task { await viewModel.exportSyncLog() }
                    }
                    .accessibilityLabel("Скопировать журнал синхронизации")

                    if let infoMessage = viewModel.infoMessage {
                        Text(infoMessage)
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.accent)
                            .accessibilityLabel(infoMessage)
                    }
                }
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.top, FFSpacing.md)

            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    Text("Диагностика синхронизации")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)
                    Text("Операций в очереди: \(viewModel.diagnostics.pendingSyncOperations)")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                    Text("Последняя попытка: \(viewModel.diagnostics.lastSyncAttemptLabel)")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                    Text("Последняя ошибка: \(viewModel.diagnostics.lastSyncError ?? "—")")
                        .font(FFTypography.caption)
                        .foregroundStyle(
                            viewModel.diagnostics.lastSyncError == nil ? FFColors.textSecondary : FFColors.danger,
                        )
                }
            }
            .padding(.horizontal, FFSpacing.md)

            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    Text("Версия приложения: \(viewModel.diagnostics.versionLabel)")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                    Text("Сборка: \(viewModel.diagnostics.buildLabel)")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.gray300)
                }
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.bottom, FFSpacing.md)
        }
        .background(FFColors.background)
        .navigationTitle("Помощь и диагностика")
        .navigationBarBackButtonHidden(false)
        .sheet(isPresented: $isMailComposerPresented) {
            MailComposerView(
                subject: "Проблема в приложении",
                body: "\n\n--- Диагностика ---\n\(viewModel.diagnosticsText)",
                recipients: ["support@fitfluence.app"],
            )
        }
        .alert("Почта недоступна", isPresented: $isMailFallbackAlertPresented) {
            Button("Открыть почтовое приложение") {
                let encoded = "support@fitfluence.app"
                let subject = "Проблема в приложении".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                    ?? "Проблема"
                if let url = URL(string: "mailto:\(encoded)?subject=\(subject)") {
                    openURL(url)
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("На устройстве не настроен почтовый аккаунт. Откроем внешний почтовый клиент.")
        }
    }
}

private struct MailComposerView: UIViewControllerRepresentable {
    let subject: String
    let body: String
    let recipients: [String]

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.setSubject(subject)
        controller.setToRecipients(recipients)
        controller.setMessageBody(body, isHTML: false)
        controller.mailComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_: MFMailComposeViewController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func mailComposeController(
            _: MFMailComposeViewController,
            didFinishWith _: MFMailComposeResult,
            error _: Error?,
        ) {
            dismiss()
        }
    }
}
