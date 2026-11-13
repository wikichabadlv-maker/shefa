import SwiftUI

/// Choose a city for the day's times, or follow the iPhone's own location.
struct CityPicker: View {
    @AppStorage(City.storageKey) private var cityID = ""
    @State private var finder = LocationFinder.shared

    private var selection: Binding<String> {
        Binding(
            get: { cityID.isEmpty ? City.all[0].id : cityID },
            set: { value in
                cityID = value
                if value == City.deviceID { finder.refresh() }
            })
    }

    var body: some View {
        Picker("מקום", selection: selection) {
            Label("לפי מיקום המכשיר", systemImage: "location.fill").tag(City.deviceID)
            ForEach(City.all) { city in
                Text(city.name).tag(city.id)
            }
        }
    }
}

/// The halachic times of the day, on their own screen.
struct ZmanimView: View {
    @AppStorage(City.storageKey) private var cityID = ""
    @State private var finder = LocationFinder.shared
    @State private var day = Calendar.current.startOfDay(for: .now)

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let _ = finder.version
            let now = timeline.date
            let city = City.find(cityID)
            let zmanim = Zmanim(city: city, day: isToday ? now : day.addingTimeInterval(12 * 3600))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    DayStrip(day: $day)
                    SunCard(zmanim: zmanim, now: now, isToday: isToday)

                    if cityID == City.deviceID {
                        deviceNote
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("זמני היום · \(city.name)")
                            .font(.system(size: 20, weight: .heavy))
                            .padding(.bottom, 6)
                        ForEach(zmanim.list) { zman in
                            let isNext = isToday && zmanim.next(after: now)?.id == zman.id
                            HStack {
                                Image(systemName: zman.symbol)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.amberInk)
                                    .frame(width: 34, height: 30)
                                    .background(Theme.amberGround, in: Capsule())
                                Text(zman.title)
                                    .font(.system(size: 16, weight: zman.isMain ? .bold : .regular))
                                if isNext {
                                    Text("הבא")
                                        .font(.system(size: 11, weight: .heavy))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .frame(height: 20)
                                        .background(Theme.accent, in: Capsule())
                                }
                                Spacer()
                                Text(zmanim.clock(zman.date))
                                    .font(.system(size: 17, weight: .heavy))
                                    .monospacedDigit()
                            }
                            .frame(height: 44)
                            .opacity(isToday && zman.date < now ? 0.45 : 1)
                            .accessibilityElement(children: .combine)
                            if zman.id != zmanim.list.last?.id { Divider() }
                        }
                    }
                    .padding(16)
                    .cardSurface()

                    Text("הזמנים מחושבים באפליקציה לפי שיטת אדמו״ר הזקן, בגובה פני הים, ועשויים לסטות בדקה או שתיים מהלוחות. לא להמתין לרגע האחרון. תזכורות לזמנים אפשר להפעיל בהגדרות.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(Theme.ground)
        .navigationTitle("זמני היום")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    CityPicker()
                } label: {
                    Text(City.find(cityID).name)
                        .font(.system(size: 15, weight: .bold))
                }
            }
        }
    }

    @ViewBuilder
    private var deviceNote: some View {
        if finder.isWorking {
            Label("מאתרים את המיקום…", systemImage: "location.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
        } else if let problem = finder.problem {
            Label(problem, systemImage: "location.slash.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.amberInk)
                .padding(.horizontal, 6)
        } else if City.device == nil {
            Button("איתור המיקום שלי", systemImage: "location.fill") { finder.refresh() }
                .font(.system(size: 15, weight: .bold))
                .padding(.horizontal, 6)
        }
    }
}

/// The day's times on the Home screen: the next one, and the ones after it.
struct ZmanimCard: View {
    @AppStorage(City.storageKey) private var cityID = ""
    @State private var finder = LocationFinder.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let _ = finder.version
            let now = timeline.date
            let zmanim = Zmanim(city: City.find(cityID), day: now)
            let next = zmanim.next(after: now, mainOnly: true)
            let upcoming = Array(zmanim.list.filter { $0.isMain && $0.date > now }.dropFirst().prefix(3))
            NavigationLink {
                ZmanimView()
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ArtworkIcon(artwork: Theme.amber, symbol: next?.symbol ?? "moon.stars.fill")
                        VStack(alignment: .leading, spacing: 1) {
                            Text(next?.title ?? "זמני היום")
                                .font(.system(size: 17, weight: .heavy))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                            Text(next.map { item -> String in
                                let minutes = max(Int(item.date.timeIntervalSince(now) / 60), 0)
                                return "בעוד \(NowStatus.duration(minutes)) · \(zmanim.city.name)"
                            } ?? "זמני מחר יופיעו אחרי חצות · \(zmanim.city.name)")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if let next {
                            Text(zmanim.clock(next.date))
                                .font(.system(size: 24, weight: .heavy))
                                .monospacedDigit()
                                .foregroundStyle(Theme.amberInk)
                        }
                    }
                    if !upcoming.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(upcoming) { zman in
                                VStack(spacing: 2) {
                                    Text(zmanim.clock(zman.date))
                                        .font(.system(size: 16, weight: .heavy))
                                        .monospacedDigit()
                                    Text(zman.title)
                                        .font(.system(size: 11, weight: .semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .foregroundStyle(Theme.amberInk)
                                .background(Theme.amberGround, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }
                }
                .padding(14)
                .cardSurface()
            }
            .buttonStyle(.pressable)
        }
    }
}
