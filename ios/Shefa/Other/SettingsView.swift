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
    @AppStorage(Coach.enabledKey) private var notifyCoach = true
    @AppStorage(CalendarFeed.remindKey) private var notifyCalendar = true
    @State private var calendarFeed = CalendarFeed.shared
    @State private var backup = Backup.shared
    @State private var showsQuestions = false
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
    @State private var plan = FinancePlan.shared

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
                Section {
                    LabeledContent("גיבוי אחרון", value: backup.lastSaved.map {
                        $0.formatted(Date.FormatStyle(locale: Ledger.hebrew).weekday(.abbreviated).hour().minute())
                    } ?? "עוד לא בוצע")
                    Button("גיבוי עכשיו", systemImage: "icloud.and.arrow.up") {
                        Task { await backup.sync(in: context, force: true) }
                    }
                    if let error = backup.lastError {
                        Text("הגיבוי לא הצליח: " + error).foregroundStyle(.red)
                    }
                } header: {
                    Text("גיבוי")
                } footer: {
                    Text("כל מה שמוזן באפליקציה נשמר בענן תוך דקה: מטלות, קניות, לו״ז, יעדים, קביעות היום, שיעורים, ספרים והגדרות. אחרי התקנה מחדש מתחברים, והכול חוזר. גם אם האפליקציה מפסיקה להיפתח כי לא חודשה בזמן, התוכן נשאר במכשיר ובענן.")
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
                    Text("אחרי הכניסה מגיעות לכאן תנועות הבנק והאשראי, הרשימות, היעדים והלו״ז משותפים לשני הטלפונים, וכל התוכן מגובה בענן. בלי כניסה אין גיבוי.")
                }
            }

            Section {
                NavigationLink {
                    SystemStatusView()
                } label: {
                    Label("מצב החיבורים", systemImage: "antenna.radiowaves.left.and.right")
                }
            } footer: {
                Text("מה מחובר, מתי התעדכן, ומה עושים כשמשהו נתקע.")
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
                Toggle("מאמן אישי: תקציר בוקר, השעה הצלולה, תכנון ערב וקניות", isOn: $notifyCoach)
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
            .onChange(of: [notifySchedule, notifyTasks, notifyCandles, notifyShma, notifySunset, notifyCoach]) { _, _ in
                remindersChanged()
            }
            .onChange(of: cityID) { _, _ in
                Notifier.shared.refresh(in: context)
            }

            Section {
                Toggle("אירועים וימי הולדת מלוח השנה", isOn: Binding(get: { calendarFeed.isOn }, set: { isOn in
                    if isOn {
                        Task {
                            await calendarFeed.turnOn()
                            Notifier.shared.refresh(in: context)
                        }
                    } else {
                        calendarFeed.turnOff()
                        Notifier.shared.refresh(in: context)
                    }
                }))
                if calendarFeed.isOn {
                    Toggle("תזכורת בבוקר של יום הולדת, ובערב שלפניו", isOn: $notifyCalendar)
                }
            } header: {
                Text("לוח השנה של אפל")
            } footer: {
                Text(calendarFeed.isDenied
                     ? "הגישה ללוח השנה חסומה. אפשר לפתוח אותה בהגדרות האייפון, תחת שפע, לוחות שנה, גישה מלאה."
                     : "האפליקציה רק קוראת את לוח השנה ומציגה ימי הולדת ואירועים בדף הבית ובלו״ז. דבר לא נשלח מהמכשיר.")
            }
            .onChange(of: notifyCalendar) { _, _ in
                Notifier.shared.refresh(in: context)
            }

            Section {
                Toggle("צלילים", isOn: $soundsOn)
            } footer: {
                Text("צליל קצר כשמסיימים מטלה או יום שלם. כשהאייפון על שקט מרגישים רק רטט.")
            }

            Section {
                Button("שאלות ההיכרות", systemImage: "sparkles") { showsQuestions = true }
            } footer: {
                Text("לפי התשובות האפליקציה מתאימה את ההתראות וההצעות. אפשר לשנות בכל רגע.")
            }
            .sheet(isPresented: $showsQuestions, onDismiss: { Notifier.shared.refresh(in: context) }) {
                CoachQuestionsSheet()
            }

            Section("כספים") {
                Toggle("נותנים חומש (20%) במקום מעשר",
                       isOn: Binding(get: { plan.isChomesh }, set: { plan.setChomesh($0) }))
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
                if let expiry = Signing.expiry, Signing.daysLeft != nil {
                    LabeledContent("לחדש ב-SideStore עד",
                                   value: expiry.formatted(Date.FormatStyle(locale: Ledger.hebrew).weekday(.wide).day().month(.wide)))
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
