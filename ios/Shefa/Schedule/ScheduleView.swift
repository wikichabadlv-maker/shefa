import SwiftData
import SwiftUI

/// The family's own day: the fixed parts they set, one-time items, and what
/// was already done. Halachic times live on their own screen.
struct ScheduleView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<ScheduleItem> { !$0.removed }, sort: \ScheduleItem.startMinute)
    private var items: [ScheduleItem]
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var editing: ScheduleItem?
    @State private var draft: ScheduleDraft?

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    private var todays: [ScheduleItem] { NowStatus.today(items, on: day) }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                content(now: timeline.date)
            }
            .navigationTitle("לו״ז")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("הוספה ללו״ז", systemImage: "plus") {
                        draft = ScheduleDraft()
                    }
                }
            }
            .sheet(item: $editing) { item in
                ScheduleEditor(item: item, draft: ScheduleDraft(item), day: day)
            }
            .sheet(item: $draft) { value in
                ScheduleEditor(item: nil, draft: value, day: day)
            }
        }
    }

    private func content(now: Date) -> some View {
        // The screen wears the colors of the sky at this hour.
        let sky: Sky = isToday ? Sky.now(now) : Sky.midday
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DayStrip(day: $day, artwork: sky.artwork)
                    .cascade(0)
                DayHero(items: todays, day: day, now: now, isToday: isToday, sky: sky)
                    .cascade(1)
                QuickScheduleBar(day: day, todays: todays)
                    .cascade(2)
                CalendarDayCard(day: day)
                    .cascade(3)
                timeline(now: now)
                    .cascade(4)
                if isToday {
                    HabitsCard()
                        .cascade(5)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background { AmbientGround(artwork: sky.artwork) }
    }

    // MARK: Timeline

    private func timeline(now: Date) -> some View {
        let list = todays
        let minute = ScheduleItem.minute(of: now)
        return VStack(alignment: .leading, spacing: 10) {
            Text(isToday ? "סדר היום" : "סדר היום ב\(HebrewDate.weekday(day))")
                .font(.system(size: 22, weight: .heavy))
                .padding(.horizontal, 4)
            if list.isEmpty {
                Text(items.isEmpty ? "עוד לא הוספתם דבר ללו״ז. נגיעה באחת ההצעות למעלה מוסיפה אותה מיד." : "אין דברים בלו״ז ליום הזה.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(list) { item in
                        let isDone = item.isDone(on: day)
                        let isNow = isToday && item.startMinute <= minute && minute < item.endMinute
                        let isPast = isToday && item.endMinute <= minute
                        row(item, isDone: isDone, isNow: isNow, isPast: isPast)
                            .transition(.sectionSwap)
                        if item.id != list.last?.id {
                            Divider().padding(.leading, 112)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .cardSurface()
            }
        }
    }

    private func row(_ item: ScheduleItem, isDone: Bool, isNow: Bool, isPast: Bool) -> some View {
        HStack(spacing: 12) {
            Button {
                editing = item
            } label: {
                HStack(spacing: 12) {
                    Text(ScheduleItem.clock(item.startMinute))
                        .font(.system(size: 15, weight: .bold))
                        .monospacedDigit()
                        .frame(width: 46, alignment: .leading)
                    ArtworkIcon(artwork: item.artwork, symbol: item.symbol, size: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.system(size: 16, weight: .bold))
                            .strikethrough(isDone)
                            .lineLimit(1)
                        Text(item.onlyDay.isEmpty ? NowStatus.duration(item.durationMinutes)
                             : "\(NowStatus.duration(item.durationMinutes)) · חד פעמי")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if isNow {
                        Text("עכשיו")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(Theme.accent, in: Capsule())
                    }
                }
                .foregroundStyle(Color.primary)
                .opacity(isDone || (isPast && !isNow) ? 0.5 : 1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)

            // The check button gives the tap, the chime and the sparks.
            CheckButton(isDone: isDone) {
                withAnimation(.spring(duration: 0.35, bounce: 0.2)) { item.setDone(!isDone, on: day) }
                try? context.save()
                SharedSync.shared.changed(in: context)
                if !isDone, isToday {
                    ScheduleItem.celebrateIfDayDone(in: context)
                }
            }
        }
        .frame(minHeight: 58)
        .contextMenu {
            Button("להקדים ברבע שעה", systemImage: "arrow.up") { shift(item, by: -15) }
            Button("לדחות ברבע שעה", systemImage: "arrow.down") { shift(item, by: 15) }
            Button("לקצר ברבע שעה", systemImage: "minus") { stretch(item, by: -15) }
            Button("להאריך ברבע שעה", systemImage: "plus") { stretch(item, by: 15) }
            Button("עריכה", systemImage: "pencil") { editing = item }
            Button("מחיקה", systemImage: "trash", role: .destructive) {
                withAnimation(.section) {
                    item.removed = true
                    item.updatedAt = .now
                }
                changed()
            }
        }
    }

    private func shift(_ item: ScheduleItem, by minutes: Int) {
        withAnimation(.section) {
            item.startMinute = min(max(item.startMinute + minutes, 0), 23 * 60 + 45)
            item.updatedAt = .now
        }
        changed()
    }

    private func stretch(_ item: ScheduleItem, by minutes: Int) {
        withAnimation(.section) {
            item.durationMinutes = max(item.durationMinutes + minutes, 5)
            item.updatedAt = .now
        }
        changed()
    }

    private func changed() {
        try? context.save()
        SharedSync.shared.changed(in: context)
        Notifier.shared.refresh(in: context)
        Feedback.tap()
    }
}

/// The colorful summary of the day's schedule.
struct DayHero: View {
    let items: [ScheduleItem]
    let day: Date
    let now: Date
    let isToday: Bool
    var sky: Sky = .midday

    private var done: Int { items.filter { $0.isDone(on: day) }.count }

    private var headline: String {
        if items.isEmpty { return "יום פתוח" }
        if done == items.count { return "היום הושלם" }
        return "\(done) מתוך \(items.count) הושלמו"
    }

    private var line: String {
        let planned = items.reduce(0) { $0 + $1.durationMinutes }
        guard isToday else {
            return items.isEmpty ? "אין דברים קבועים ביום הזה." : "מתוכננות \(NowStatus.duration(planned))."
        }
        if items.isEmpty { return "הוסיפו את החלק הראשון של היום." }
        let status = NowStatus.make(items: items, now: now)
        if status.item != nil { return "\(status.title) · \(status.detail)" }
        return done == items.count ? "כל הכבוד. מחר ממשיכים." : "הלו״ז של היום מאחוריכם. אפשר לסמן מה בוצע."
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(HebrewDate.weekday(day)) · \(HebrewDate.text(day))")
                    .font(.system(size: 14, weight: .bold))
                    .opacity(0.9)
                Text(headline)
                    .font(.system(size: 30, weight: .heavy))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(line)
                    .font(.system(size: 13, weight: .medium))
                    .opacity(0.92)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            ProgressRing(share: items.isEmpty ? 0 : Double(done) / Double(items.count), lineWidth: 10)
                .frame(width: 84, height: 84)
                .overlay {
                    Image(systemName: !items.isEmpty && done == items.count ? "checkmark" : "calendar")
                        .font(.system(size: 26, weight: .heavy))
                }
        }
        .foregroundStyle(.white)
        .padding(20)
        .background {
            if sky.isNight {
                StarField(count: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
        }
        .livingCard(sky.artwork, seed: 0.2)
        .animation(.smooth(duration: 0.6), value: sky.artwork)
        .accessibilityElement(children: .combine)
    }
}

/// Seven days to move between, starting today.
struct DayStrip: View {
    @Binding var day: Date
    /// The color of the chosen day.
    var artwork: Artwork = Theme.emerald
    /// On a colorful ground the days are glass and the chosen one is white.
    var isOnSky = false

    private var days: [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(days, id: \.self) { item in
                let isOn = Calendar.current.isDate(item, inSameDayAs: day)
                let index = Calendar.current.component(.weekday, from: item) - 1
                Button {
                    withAnimation(.snappy) { day = item }
                } label: {
                    VStack(spacing: 2) {
                        Text(ScheduleItem.dayLetters[index] + "׳")
                            .font(.system(size: 12, weight: .semibold))
                            .opacity(0.8)
                        Text("\(Calendar.current.component(.day, from: item))")
                            .font(.system(size: 17, weight: .heavy))
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(isOnSky ? (isOn ? artwork.end : Color.white)
                                     : (isOn ? Color.white : Color.primary))
                    .background(isOnSky
                                ? (isOn ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.16)))
                                : (isOn ? AnyShapeStyle(artwork.gradient) : AnyShapeStyle(Theme.card)),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

/// The top of the times screen, drawn straight on the sky: the sun's path,
/// and the next time of the day.
struct SkyHeader: View {
    let zmanim: Zmanim
    let now: Date
    let isToday: Bool

    private var share: Double { zmanim.dayShare(at: now) }

    private var headline: (String, String) {
        guard isToday else {
            return (HebrewDate.weekday(zmanim.day), HebrewDate.text(zmanim.day))
        }
        if let next = zmanim.next(after: now, mainOnly: true) {
            let minutes = max(Int(next.date.timeIntervalSince(now) / 60), 0)
            return (next.title, "בעוד \(NowStatus.duration(minutes)) · \(zmanim.clock(next.date))")
        }
        return ("לילה טוב", "זמני מחר יופיעו אחרי חצות")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(HebrewDate.weekday(zmanim.day)) · \(HebrewDate.text(zmanim.day))")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Text(zmanim.day.formatted(Date.FormatStyle(locale: Ledger.hebrew).day().month(.wide)))
                    .font(.system(size: 14, weight: .semibold))
                    .opacity(0.85)
            }
            SunArc(share: isToday ? share : 0.5, showsSun: isToday)
                .frame(height: 156)
                .environment(\.layoutDirection, .leftToRight)
                .overlay(alignment: .bottom) {
                    VStack(spacing: 0) {
                        Text(headline.0)
                            .font(.system(size: 30, weight: .heavy))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(headline.1)
                            .font(.system(size: 15, weight: .semibold))
                            .opacity(0.92)
                    }
                    .padding(.bottom, 2)
                }
            HStack {
                edge("שקיעה", zmanim.sunset, "sunset.fill")
                Spacer()
                edge("זריחה", zmanim.sunrise, "sunrise.fill")
            }
            .environment(\.layoutDirection, .leftToRight)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private func edge(_ title: String, _ date: Date?, _ symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
            Text(date.map { zmanim.clock($0) } ?? "--:--")
                .font(.system(size: 16, weight: .heavy))
                .monospacedDigit()
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .opacity(0.85)
        }
    }
}

/// A dotted half circle with the sun on it. When the screen opens, the sun
/// travels from the sunrise to where it stands now.
struct SunArc: View {
    let share: Double
    var showsSun = true
    @Environment(\.arrived) private var arrived
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SunPath(share: arrived || reduceMotion ? share : min(share, 0), showsSun: showsSun)
            .animation(.smooth(duration: 1.4).delay(0.2), value: arrived)
            .accessibilityHidden(true)
    }
}

/// The drawing behind `SunArc`, for every point of the sun's way.
private struct SunPath: View, Animatable {
    var share: Double
    let showsSun: Bool

    var animatableData: Double {
        get { share }
        set { share = newValue }
    }

    var body: some View {
        GeometryReader { proxy in
            let radius: CGFloat = min(proxy.size.width / 2 - 14, proxy.size.height - 16)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height - 2)
            let clamped: Double = min(max(share, 0), 1)
            // The sun rises in the east, drawn here on the right as on a map facing south.
            let angle = Angle.degrees(360 - 180 * clamped)
            let sun = CGPoint(x: center.x + radius * CGFloat(cos(angle.radians)),
                              y: center.y + radius * CGFloat(sin(angle.radians)))
            ZStack {
                Path { path in
                    path.addArc(center: center, radius: radius, startAngle: .degrees(180),
                                endAngle: .degrees(360), clockwise: false)
                }
                .stroke(.white.opacity(0.4), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 8]))

                if showsSun && share > 0 {
                    Path { path in
                        path.addArc(center: center, radius: radius, startAngle: angle,
                                    endAngle: .degrees(360), clockwise: false)
                    }
                    .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                }
                if showsSun && share >= 0 && share <= 1 {
                    Circle()
                        .fill(Color(hex: 0xFDE68A))
                        .frame(width: 26, height: 26)
                        .shadow(color: Color(hex: 0xFDE68A).opacity(0.9), radius: 14)
                        .position(sun)
                }
            }
        }
    }
}

/// What the editor works on before saving.
struct ScheduleDraft: Identifiable {
    let id = UUID()
    var title = ""
    var start = 8 * 60
    var duration = 60
    var weekdays = ScheduleItem.weekdaysMask
    var symbol = "clock.fill"
    var palette = 0
    var isOnce = false

    init() {}

    init(title: String, start: Int, duration: Int, weekdays: Int = ScheduleItem.weekdaysMask,
         symbol: String, palette: Int) {
        self.title = title
        self.start = start
        self.duration = duration
        self.weekdays = weekdays
        self.symbol = symbol
        self.palette = palette
    }

    init(_ item: ScheduleItem) {
        title = item.title
        start = item.startMinute
        duration = item.durationMinutes
        weekdays = item.weekdays
        symbol = item.symbol
        palette = item.palette
        isOnce = !item.onlyDay.isEmpty
    }
}

/// Add or change one fixed part of the day.
struct ScheduleEditor: View {
    let item: ScheduleItem?
    @State var draft: ScheduleDraft
    let day: Date
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    static let symbols = ["clock.fill", "sunrise.fill", "book.fill", "briefcase.fill", "person.2.fill",
                          "heart.fill", "figure.walk", "fork.knife", "moon.fill", "cart.fill",
                          "graduationcap.fill", "bed.double.fill"]
    private let durations = [10, 15, 20, 30, 45, 60, 90, 120, 180, 240, 360, 480]

    private var startDate: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: draft.start / 60, minute: draft.start % 60, second: 0, of: .now) ?? .now
            },
            set: { draft.start = ScheduleItem.minute(of: $0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("מה עושים? למשל חברותא", text: $draft.title)
                    DatePicker("שעת התחלה", selection: startDate, displayedComponents: .hourAndMinute)
                    Picker("משך", selection: $draft.duration) {
                        ForEach(durations, id: \.self) { value in
                            Text(NowStatus.duration(value)).tag(value)
                        }
                    }
                }
                Section {
                    Toggle("חד פעמי, רק ב\(HebrewDate.weekday(day)) \(HebrewDate.text(day))", isOn: $draft.isOnce)
                }
                if !draft.isOnce {
                Section("באילו ימים") {
                    HStack(spacing: 6) {
                        ForEach(0..<7, id: \.self) { index in
                            let isOn = draft.weekdays & (1 << index) != 0
                            Button {
                                draft.weekdays ^= (1 << index)
                            } label: {
                                Text(ScheduleItem.dayLetters[index])
                                    .font(.system(size: 16, weight: .bold))
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .foregroundStyle(isOn ? Color.white : Color.primary)
                                    .background(isOn ? Theme.accent : Theme.chip, in: Circle())
                            }
                            .buttonStyle(.pressable)
                            .accessibilityAddTraits(isOn ? .isSelected : [])
                        }
                    }
                }
                }
                Section("מראה") {
                    SymbolGrid(symbols: ScheduleEditor.symbols, selection: $draft.symbol)
                    PaletteRow(selection: $draft.palette)
                }
                if let item {
                    Section {
                        Button("מחיקה מהלו״ז", role: .destructive) {
                            item.removed = true
                            item.updatedAt = .now
                            finish()
                        }
                    }
                }
            }
            .navigationTitle(item == nil ? "חדש בלו״ז" : "עריכה")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה") { save() }
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty
                                  || (!draft.isOnce && draft.weekdays == 0))
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func save() {
        let title = draft.title.trimmingCharacters(in: .whitespaces)
        if let item {
            item.title = title
            item.startMinute = draft.start
            item.durationMinutes = draft.duration
            item.weekdays = draft.weekdays
            item.symbol = draft.symbol
            item.palette = draft.palette
            item.onlyDay = draft.isOnce ? (item.onlyDay.isEmpty ? DayKey.of(day) : item.onlyDay) : ""
            item.updatedAt = .now
        } else {
            let created = ScheduleItem(
                title: title, startMinute: draft.start, durationMinutes: draft.duration,
                weekdays: draft.weekdays, symbol: draft.symbol, palette: draft.palette)
            created.onlyDay = draft.isOnce ? DayKey.of(day) : ""
            context.insert(created)
            Feedback.added()
            Task { _ = await Notifier.shared.askPermission() }
        }
        finish()
    }

    private func finish() {
        try? context.save()
        SharedSync.shared.changed(in: context)
        Notifier.shared.refresh(in: context)
        dismiss()
    }
}

/// A grid of symbols to choose one from.
struct SymbolGrid: View {
    let symbols: [String]
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
            ForEach(symbols, id: \.self) { item in
                Button {
                    selection = item
                } label: {
                    Image(systemName: item)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(selection == item ? Color.white : Color.primary)
                        .background(selection == item ? Theme.accent : Theme.chip,
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(selection == item ? .isSelected : [])
            }
        }
    }
}

/// A row of color choices.
struct PaletteRow: View {
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(SavingsGoal.palettes.indices, id: \.self) { index in
                Button {
                    selection = index
                } label: {
                    Circle()
                        .fill(SavingsGoal.palettes[index].gradient)
                        .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
                        .overlay {
                            if selection == index {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("צבע \(index + 1)")
                .accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }
    }
}
