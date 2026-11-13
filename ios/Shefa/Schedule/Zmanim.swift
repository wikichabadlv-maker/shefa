import Foundation

/// A place the day's times are calculated for.
struct City: Identifiable, Hashable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let zone: String
    /// Minutes before sunset for lighting Shabbat candles, by local custom.
    let candles: Int

    var timeZone: TimeZone { TimeZone(identifier: zone) ?? .current }

    /// The first one is the default.
    static let all: [City] = [
        City(id: "kiryat-gat", name: "קריית גת", latitude: 31.610, longitude: 34.764, zone: "Asia/Jerusalem", candles: 20),
        City(id: "jerusalem", name: "ירושלים", latitude: 31.778, longitude: 35.235, zone: "Asia/Jerusalem", candles: 40),
        City(id: "kfar-chabad", name: "כפר חב״ד", latitude: 31.989, longitude: 34.852, zone: "Asia/Jerusalem", candles: 20),
        City(id: "tel-aviv", name: "תל אביב", latitude: 32.080, longitude: 34.780, zone: "Asia/Jerusalem", candles: 20),
        City(id: "bnei-brak", name: "בני ברק", latitude: 32.084, longitude: 34.834, zone: "Asia/Jerusalem", candles: 20),
        City(id: "lod", name: "לוד", latitude: 31.951, longitude: 34.888, zone: "Asia/Jerusalem", candles: 20),
        City(id: "haifa", name: "חיפה", latitude: 32.794, longitude: 34.990, zone: "Asia/Jerusalem", candles: 22),
        City(id: "tzfat", name: "צפת", latitude: 32.965, longitude: 35.496, zone: "Asia/Jerusalem", candles: 22),
        City(id: "kiryat-malachi", name: "נחלת הר חב״ד", latitude: 31.730, longitude: 34.745, zone: "Asia/Jerusalem", candles: 20),
        City(id: "beitar", name: "ביתר עילית", latitude: 31.697, longitude: 35.116, zone: "Asia/Jerusalem", candles: 20),
        City(id: "ashdod", name: "אשדוד", latitude: 31.804, longitude: 34.655, zone: "Asia/Jerusalem", candles: 20),
        City(id: "beer-sheva", name: "באר שבע", latitude: 31.252, longitude: 34.791, zone: "Asia/Jerusalem", candles: 20),
        City(id: "eilat", name: "אילת", latitude: 29.558, longitude: 34.948, zone: "Asia/Jerusalem", candles: 20),
        City(id: "new-york", name: "ניו יורק", latitude: 40.669, longitude: -73.943, zone: "America/New_York", candles: 18),
    ]

    static let storageKey = "cityID"
    /// The choice that follows the iPhone's own location.
    static let deviceID = "device"

    /// The last place the iPhone reported, if location was ever allowed.
    static var device: City? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "deviceLatitude") != nil else { return nil }
        return City(id: deviceID, name: defaults.string(forKey: "deviceName") ?? "המיקום שלי",
                    latitude: defaults.double(forKey: "deviceLatitude"),
                    longitude: defaults.double(forKey: "deviceLongitude"),
                    zone: TimeZone.current.identifier, candles: 20)
    }

    static func find(_ id: String) -> City {
        if id == deviceID, let device { return device }
        return all.first { $0.id == id } ?? all[0]
    }

    static var current: City {
        find(UserDefaults.standard.string(forKey: storageKey) ?? "")
    }
}

/// One halachic time of the day.
struct Zman: Identifiable {
    let id: String
    let title: String
    let date: Date
    let symbol: String
    /// The few times shown in short summaries.
    var isMain = false
}

/// The times of one day in one city, following the method of the Alter Rebbe:
/// halachic hours run between the "true" sunrise and sunset, when the sun is
/// 1.583 degrees below the horizon.
struct Zmanim {
    let city: City
    let day: Date
    let list: [Zman]
    let sunrise: Date?
    let sunset: Date?

    init(city: City = .current, day: Date = .now) {
        self.city = city
        self.day = day

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = city.timeZone
        let weekday = calendar.component(.weekday, from: day)

        func sun(_ zenith: Double, rising: Bool) -> Date? {
            Zmanim.sunTime(day: day, city: city, zenith: zenith, rising: rising)
        }

        let rise = sun(90.833, rising: true)
        let set = sun(90.833, rising: false)
        sunrise = rise
        sunset = set

        var result: [Zman] = []
        func add(_ id: String, _ title: String, _ date: Date?, _ symbol: String, main: Bool = false) {
            if let date { result.append(Zman(id: id, title: title, date: date, symbol: symbol, isMain: main)) }
        }

        add("alot", "עלות השחר", sun(106.9, rising: true), "moon.stars.fill")
        add("misheyakir", "זמן טלית ותפילין", sun(100.2, rising: true), "sunrise")
        add("netz", "הנץ החמה", rise, "sunrise.fill", main: true)

        if let trueRise = sun(91.583, rising: true), let trueSet = sun(91.583, rising: false) {
            let hour = trueSet.timeIntervalSince(trueRise) / 12
            add("shma", "סוף זמן קריאת שמע", trueRise.addingTimeInterval(hour * 3), "book.fill", main: true)
            add("tefila", "סוף זמן תפילה", trueRise.addingTimeInterval(hour * 4), "text.book.closed.fill")
            add("chatzot", "חצות היום", trueRise.addingTimeInterval(hour * 6), "sun.max.fill", main: true)
            add("mincha", "מנחה גדולה", trueRise.addingTimeInterval(hour * 6.5), "sun.min.fill")
            add("mincha-ketana", "מנחה קטנה", trueRise.addingTimeInterval(hour * 9.5), "sun.min")
            add("plag", "פלג המנחה", trueRise.addingTimeInterval(hour * 10.75), "sun.horizon")
        }

        if weekday == 6, let set {
            add("candles", "הדלקת נרות שבת", set.addingTimeInterval(Double(-city.candles) * 60), "flame.fill", main: true)
        }
        add("shkia", "שקיעת החמה", set, "sunset.fill", main: true)
        if weekday == 7 {
            add("shabbat-end", "צאת השבת", sun(98.5, rising: false), "sparkles", main: true)
        } else {
            add("tzeit", "צאת הכוכבים", sun(96, rising: false), "moon.fill", main: true)
        }
        list = result.sorted { $0.date < $1.date }
    }

    /// The next time that has not passed yet.
    func next(after now: Date = .now, mainOnly: Bool = false) -> Zman? {
        list.first { $0.date > now && (!mainOnly || $0.isMain) }
    }

    /// How far the sun is through the day, from 0 at sunrise to 1 at sunset.
    func dayShare(at now: Date = .now) -> Double {
        guard let sunrise, let sunset, sunset > sunrise else { return 0 }
        return now.timeIntervalSince(sunrise) / sunset.timeIntervalSince(sunrise)
    }

    func clock(_ date: Date) -> String {
        Zmanim.clock(date, zone: city.timeZone)
    }

    static func clock(_ date: Date, zone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "H:mm"
        return formatter.string(from: date)
    }

    /// When the sun reaches a given angle from the zenith, by the standard
    /// almanac method. Accurate to about a minute at sea level.
    static func sunTime(day: Date, city: City, zenith: Double, rising: Bool) -> Date? {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = city.timeZone
        let parts = local.dateComponents([.year, .month, .day], from: day)
        guard let dayOfYear = local.ordinality(of: .day, in: .year, for: day) else { return nil }

        func rad(_ degrees: Double) -> Double { degrees * .pi / 180 }
        func deg(_ radians: Double) -> Double { radians * 180 / .pi }
        func wrap(_ value: Double, _ size: Double) -> Double {
            let rest = value.truncatingRemainder(dividingBy: size)
            return rest < 0 ? rest + size : rest
        }

        let longitudeHour = city.longitude / 15
        let t = Double(dayOfYear) + ((rising ? 6.0 : 18.0) - longitudeHour) / 24
        let anomaly = 0.9856 * t - 3.289
        let longitude = wrap(anomaly + 1.916 * sin(rad(anomaly)) + 0.020 * sin(rad(2 * anomaly)) + 282.634, 360)
        var ascension = wrap(deg(atan(0.91764 * tan(rad(longitude)))), 360)
        ascension += (longitude / 90).rounded(.down) * 90 - (ascension / 90).rounded(.down) * 90
        ascension /= 15

        let sinDeclination = 0.39782 * sin(rad(longitude))
        let cosDeclination = cos(asin(sinDeclination))
        let cosHour = (cos(rad(zenith)) - sinDeclination * sin(rad(city.latitude)))
            / (cosDeclination * cos(rad(city.latitude)))
        guard cosHour >= -1, cosHour <= 1 else { return nil }

        let angle = rising ? 360 - deg(acos(cosHour)) : deg(acos(cosHour))
        let localMean = wrap(angle / 15 + ascension - 0.06571 * t - 6.622, 24)
        let universal = localMean - longitudeHour

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        guard let midnight = utc.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day))
        else { return nil }
        return midnight.addingTimeInterval(universal * 3600)
    }
}

enum HebrewDate {
    /// For example "ג׳ בכסלו".
    static func text(_ date: Date = .now, withYear: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .hebrew)
        formatter.locale = Locale(identifier: "he_IL@numbers=hebr")
        formatter.dateFormat = withYear ? "d בMMMM y" : "d בMMMM"
        return formatter.string(from: date)
    }

    static func weekday(_ date: Date = .now) -> String {
        date.formatted(Date.FormatStyle(locale: Locale(identifier: "he_IL")).weekday(.wide))
    }
}
