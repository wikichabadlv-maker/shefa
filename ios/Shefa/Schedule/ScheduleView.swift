import SwiftData
import SwiftUI

/// The day at a glance: the sun's path, the halachic times and the family's
/// own fixed parts of the day on one timeline.
struct ScheduleView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<ScheduleItem> { !$0.removed }, sort: \ScheduleItem.startMinute)
    private var items: [ScheduleItem]
    @AppStorage(City.storageKey) private var cityID = ""
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var editing: ScheduleItem?
    @State private var draft: ScheduleDraft?
    @State private var showsAllTimes = Launch.anchor == "times"

    private var city: City { City.find(cityID) }

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    private var todays: [ScheduleItem] {
        let weekday = Calendar.current.component(.weekday, from: day)
        return items.filter { $0.isOn(weekday: weekday) }
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                content(now: timeline.date)
            }
            .background(Theme.ground)
            .navigationTitle("לו״ז")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("הוספה ללו״ז", systemImage: "plus") {
                        draft = ScheduleDraft()
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("עיר", selection: $cityID) {
                            ForEach(City.all) { item in
                                Text(item.name).tag(item.id)
                            }
                        }
                    } label: {
                        Label(city.name, systemImage: "location.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 14, weight: .bold))
                    }
                }
            }
            .sheet(item: $editing) { item in
                ScheduleEditor(item: item, draft: ScheduleDraft(item))
            }
            .sheet(item: $draft) { value in
                ScheduleEditor(item: nil, draft: value)
            }
        }
    }

    private func content(now: Date) -> some View {
        let moment = isToday ? now : day.addingTimeInterval(12 * 3600)
        let zmanim = Zmanim(city: city, day: moment)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DayStrip(day: $day)
                SunCard(zmanim: zmanim, now: now, isToday: isToday)
                timeline(zmanim: zmanim, now: now)
                if items.isEmpty {
                    starters
                }
                allTimes(zmanim: zmanim, now: now)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    // MARK: Timeline

    private struct Row: Identifiable {
        let id: String
        let minute: Int
        let endMinute: Int
        let title: String
        let detail: String
        let symbol: String
        let artwork: Artwork
        let item: ScheduleItem?
    }

    private func rows(zmanim: Zmanim) -> [Row] {
        var result = todays.map { item in
            Row(id: item.id, minute: item.startMinute, endMinute: item.endMinute, title: item.title,
                detail: NowStatus.duration(item.durationMinutes), symbol: item.symbol,
                artwork: item.artwork, item: item)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zmanim.city.timeZone
        for zman in zmanim.list where zman.isMain {
            let parts = calendar.dateComponents([.hour, .minute], from: zman.date)
            let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            result.append(Row(id: "zman-" + zman.id, minute: minute, endMinute: minute, title: zman.title,
                              detail: "", symbol: zman.symbol, artwork: Theme.amber, item: nil))
        }
        return result.sorted { $0.minute < $1.minute }
    }

    private func timeline(zmanim: Zmanim, now: Date) -> some View {
        let list = rows(zmanim: zmanim)
        let minute = ScheduleItem.minute(of: now)
        return VStack(alignment: .leading, spacing: 10) {
            Text(isToday ? "סדר היום" : "סדר היום ב\(HebrewDate.weekday(day))")
                .font(.system(size: 22, weight: .heavy))
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(list) { row in
                    let isPast = isToday && row.endMinute <= minute && row.item != nil
                        || isToday && row.item == nil && row.minute < minute
                    let isNow = isToday && row.item != nil && row.minute <= minute && minute < row.endMinute
                    Button {
                        if let item = row.item { editing = item }
                    } label: {
                        timelineRow(row, isPast: isPast, isNow: isNow)
                    }
                    .buttonStyle(.plain)
                    .disabled(row.item == nil)
                    if row.id != list.last?.id {
                        Divider().padding(.leading, 112)
                    }
                }
            }
            .padding(.horizontal, 14)
            .cardSurface()
        }
    }

    private func timelineRow(_ row: Row, isPast: Bool, isNow: Bool) -> some View {
        HStack(spacing: 12) {
            Text(ScheduleItem.clock(row.minute))
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(row.item == nil ? Theme.amberInk : Color.primary)
                .frame(width: 46, alignment: .leading)
            if row.item == nil {
                Image(systemName: row.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.amberInk)
                    .frame(width: 38, height: 30)
                    .background(Theme.amberGround, in: Capsule())
            } else {
                ArtworkIcon(artwork: row.artwork, symbol: row.symbol, size: 38)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(.system(size: row.item == nil ? 14 : 16, weight: row.item == nil ? .semibold : .bold))
                    .foregroundStyle(row.item == nil ? Theme.amberInk : Color.primary)
                    .lineLimit(1)
                if !row.detail.isEmpty {
                    Text(row.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
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
        .frame(minHeight: row.item == nil ? 44 : 58)
        .opacity(isPast ? 0.45 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: Starters

    private var starters: some View {
        let ideas: [ScheduleDraft] = [
            ScheduleDraft(title: "שחרית", start: 7 * 60, duration: 60, symbol: "sunrise.fill", palette: 4),
            ScheduleDraft(title: "חת״ת ורמב״ם", start: 8 * 60, duration: 30, symbol: "book.fill", palette: 0),
            ScheduleDraft(title: "עבודה", start: 9 * 60, duration: 480, weekdays: 0b0011111, symbol: "briefcase.fill", palette: 7),
            ScheduleDraft(title: "חברותא", start: 20 * 60, duration: 60, symbol: "person.2.fill", palette: 3),
            ScheduleDraft(title: "זמן זוגי", start: 21 * 60, duration: 45, symbol: "heart.fill", palette: 2),
        ]
        return VStack(alignment: .leading, spacing: 10) {
            Text("בונים את היום שלכם")
                .font(.system(size: 18, weight: .heavy))
            Text("הוסיפו את החלקים הקבועים של היום. הם ישתלבו עם זמני היום, ויופיעו גם בסרגל שמעל התפריט.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(ideas) { idea in
                        Button {
                            draft = idea
                        } label: {
                            Label(idea.title, systemImage: idea.symbol)
                                .font(.system(size: 14, weight: .bold))
                                .padding(.horizontal, 14)
                                .frame(height: 38)
                                .background(Theme.chip, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: All times

    private func allTimes(zmanim: Zmanim, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.snappy) { showsAllTimes.toggle() }
            } label: {
                HStack {
                    Text("כל זמני היום · \(zmanim.city.name)")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(Color.primary)
                    Spacer()
                    Image(systemName: showsAllTimes ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsAllTimes {
                ForEach(zmanim.list) { zman in
                    HStack {
                        Image(systemName: zman.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.amberInk)
                            .frame(width: 26)
                        Text(zman.title)
                            .font(.system(size: 15, weight: zman.isMain ? .bold : .regular))
                        Spacer()
                        Text(zmanim.clock(zman.date))
                            .font(.system(size: 15, weight: .bold))
                            .monospacedDigit()
                    }
                    .frame(height: 34)
                    .opacity(isToday && zman.date < now ? 0.45 : 1)
                }
                Text("הזמנים מחושבים באפליקציה לפי שיטת אדמו״ר הזקן, בגובה פני הים, ועשויים לסטות בדקה או שתיים מהלוחות. לא להמתין לרגע האחרון.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
        }
        .padding(16)
        .cardSurface()
    }
}

/// Seven days to move between, starting today.
struct DayStrip: View {
    @Binding var day: Date

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
                    .foregroundStyle(isOn ? Color.white : Color.primary)
                    .background(isOn ? AnyShapeStyle(Theme.emerald.gradient) : AnyShapeStyle(Theme.card),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

/// The colorful card with the sun's path across the day.
struct SunCard: View {
    let zmanim: Zmanim
    let now: Date
    let isToday: Bool

    private var share: Double { zmanim.dayShare(at: now) }
    private var isNight: Bool { isToday && (share < 0 || share > 1) }

    private var colors: [Color] {
        if isNight { return [Color(hex: 0x312E81), Color(hex: 0x1E1B4B), Color(hex: 0x0F172A)] }
        if isToday && share > 0.8 { return [Color(hex: 0xEA580C), Color(hex: 0xDB2777), Color(hex: 0x7C3AED)] }
        return [Color(hex: 0x0EA5E9), Color(hex: 0x2563EB), Color(hex: 0x4F46E5)]
    }

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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(HebrewDate.weekday(zmanim.day)) · \(HebrewDate.text(zmanim.day))")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text(zmanim.day.formatted(Date.FormatStyle(locale: Ledger.hebrew).day().month(.wide)))
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(0.85)
            }
            SunArc(share: isToday ? share : 0.5, showsSun: isToday)
                .frame(height: 118)
                .environment(\.layoutDirection, .leftToRight)
                .overlay(alignment: .bottom) {
                    VStack(spacing: 0) {
                        Text(headline.0)
                            .font(.system(size: 20, weight: .heavy))
                        Text(headline.1)
                            .font(.system(size: 13, weight: .semibold))
                            .opacity(0.9)
                    }
                    .padding(.bottom, 4)
                }
            HStack {
                edge("שקיעה", zmanim.sunset, "sunset.fill")
                Spacer()
                edge("זריחה", zmanim.sunrise, "sunrise.fill")
            }
            .environment(\.layoutDirection, .leftToRight)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: colors[1].opacity(0.45), radius: 20, y: 12)
        .accessibilityElement(children: .combine)
    }

    private func edge(_ title: String, _ date: Date?, _ symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
            Text(date.map { zmanim.clock($0) } ?? "--:--")
                .font(.system(size: 15, weight: .heavy))
                .monospacedDigit()
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .opacity(0.85)
        }
    }
}

/// A dotted half circle with the sun on it.
struct SunArc: View {
    let share: Double
    var showsSun = true

    var body: some View {
        GeometryReader { proxy in
            let radius = min(proxy.size.width / 2 - 14, proxy.size.height - 16)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height - 2)
            let clamped = min(max(share, 0), 1)
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
                        .frame(width: 24, height: 24)
                        .shadow(color: Color(hex: 0xFDE68A).opacity(0.9), radius: 12)
                        .position(sun)
                }
            }
        }
        .accessibilityHidden(true)
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
    }
}

/// Add or change one fixed part of the day.
struct ScheduleEditor: View {
    let item: ScheduleItem?
    @State var draft: ScheduleDraft
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
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isOn ? .isSelected : [])
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
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty || draft.weekdays == 0)
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
            item.updatedAt = .now
        } else {
            context.insert(ScheduleItem(
                title: title, startMinute: draft.start, durationMinutes: draft.duration,
                weekdays: draft.weekdays, symbol: draft.symbol, palette: draft.palette))
        }
        finish()
    }

    private func finish() {
        try? context.save()
        SharedSync.shared.changed(in: context)
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
                .buttonStyle(.plain)
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
                .buttonStyle(.plain)
                .accessibilityLabel("צבע \(index + 1)")
                .accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }
    }
}
