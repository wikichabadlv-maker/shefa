import SwiftData
import SwiftUI

/// Account and sync settings.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var backend = Backend.shared
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var signInError: String?

    var body: some View {
        Form {
            if let session = backend.session {
                Section("חשבון משפחתי") {
                    LabeledContent("מחוברים בתור", value: session.email)
                    Button("התנתקות", role: .destructive) { backend.signOut() }
                }
                Section {
                    Button {
                        Task { await backend.sync(into: context) }
                    } label: {
                        HStack {
                            Text("סנכרון עכשיו")
                            Spacer()
                            if backend.isSyncing { ProgressView() }
                        }
                    }
                    .disabled(backend.isSyncing)
                    if let lastSync = backend.lastSync {
                        LabeledContent("עודכן לאחרונה",
                                       value: lastSync.formatted(Date.FormatStyle(locale: Ledger.hebrew).hour().minute()))
                    }
                    if let error = backend.lastError {
                        Text(error).foregroundStyle(.red)
                    }
                } header: {
                    Text("נתוני בנק ואשראי")
                } footer: {
                    Text("התנועות נמשכות מהבנק אוטומטית חמש פעמים ביום, ומגיעות לכאן בכל פתיחה של האפליקציה.")
                }
            } else {
                Section {
                    TextField("אימייל", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .environment(\.layoutDirection, .leftToRight)
                    SecureField("סיסמה", text: $password)
                        .textContentType(.password)
                    Button {
                        signIn()
                    } label: {
                        HStack {
                            Text("כניסה")
                            Spacer()
                            if isWorking { ProgressView() }
                        }
                    }
                    .disabled(isWorking || email.isEmpty || password.isEmpty)
                    if let signInError {
                        Text(signInError).foregroundStyle(.red)
                    }
                } header: {
                    Text("כניסה לחשבון המשפחתי")
                } footer: {
                    Text("עד הכניסה האפליקציה מציגה נתוני דוגמה בלבד.")
                }
            }
        }
        .navigationTitle("הגדרות")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func signIn() {
        isWorking = true
        signInError = nil
        Task {
            do {
                try await backend.signIn(
                    email: email.trimmingCharacters(in: .whitespaces), password: password)
                password = ""
                await backend.sync(into: context)
            } catch {
                signInError = error.localizedDescription
            }
            isWorking = false
        }
    }
}
