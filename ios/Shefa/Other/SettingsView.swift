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
    @AppStorage(City.storageKey) private var cityID = ""
    @AppStorage(Feedback.soundsKey) private var soundsOn = true
    @AppStorage(Notifier.scheduleKey) private var notifySchedule = true
    @AppStorage(Notifier.tasksKey) private var notifyTasks = true
    @AppStorage(Notifier.candlesKey) private var notifyCandles = true
    @AppStorage(Notifier.shmaKey) private var notifyShma = false
    @AppStorage(Notifier.sunsetKey) private var notifySunset = false
    @State private var finder = LocationFinder.shared
    @State private var notificationsBlocked = false

    private func remindersChanged() {
        Task {
            let allowed = await Notifier.shared.askPermission()
            notificationsBlocked = !allowed
            Notifier.shared.refresh(in: context)
        }
    }
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("givesChomesh") private var givesChomesh = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "\(short) (\(build))"
    }

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
                    Text("אחרי הכניסה מגיעות לכאן תנועות הבנק והאשראי, והרשימות, היעדים והלו״ז משותפים לשני הטלפונים.")
                }
            }

            Section {
                CityPicker()
                if cityID == City.deviceID {
                    if finder.isWorking {
                        Label("מאתרים את המיקום…", systemImage: "location.fill")
                    } else if let problem = finder.problem {
                        Text(problem).foregroundStyle(Theme.amberInk)
                    } else {
                        Button("עדכון המיקום עכשיו", systemImage: "location.fill") { finder.refresh() }
                    }
                }
            } header: {
                Text("זמני היום")
            } footer: {
                Text("הזמנים מחושבים לפי שיטת אדמו״ר הזקן. המיקום נשמר במכשיר בלבד.")
            }

            Section {
                Toggle("תחילת כל חלק בלו״ז", isOn: $notifySchedule)
                Toggle("מטלות שהגיע זמנן (8:30 בבוקר)", isOn: $notifyTasks)
                Toggle("40 דקות לפני הדלקת נרות", isOn: $notifyCandles)
                Toggle("חצי שעה לפני סוף זמן קריאת שמע", isOn: $notifyShma)
                Toggle("חצי שעה לפני השקיעה", isOn: $notifySunset)
            } header: {
                Text("תזכורות")
            } footer: {
                if notificationsBlocked {
                    Text("ההתראות כבויות לאפליקציה. אפשר להפעיל אותן בהגדרות האייפון, תחת שפע.")
                }
            }
            .onChange(of: [notifySchedule, notifyTasks, notifyCandles, notifyShma, notifySunset]) { _, _ in
                remindersChanged()
            }
            .onChange(of: cityID) { _, _ in
                Notifier.shared.refresh(in: context)
            }

            Section {
                Toggle("צלילים", isOn: $soundsOn)
            } footer: {
                Text("צליל קצר כשמסיימים מטלה או יום שלם. כשהאייפון על שקט מרגישים רק רטט.")
            }

            Section("כספים") {
                Toggle("נותנים חומש (20%) במקום מעשר", isOn: $givesChomesh)
            }

            Section("מראה") {
                Picker("מראה", selection: $appearance) {
                    Text("לפי המכשיר").tag("system")
                    Text("בהיר").tag("light")
                    Text("כהה").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section {
                LabeledContent("גרסה", value: version)
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
