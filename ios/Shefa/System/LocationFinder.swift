import CoreLocation
import Foundation
import Observation

/// Asks the iPhone where it is, once, to calculate the day's times for that
/// exact place. Only the coordinates and the town's name are kept, on the phone.
@Observable
final class LocationFinder: NSObject, CLLocationManagerDelegate {
    static let shared = LocationFinder()

    var isWorking = false
    var problem: String?
    /// Changes whenever a new place was saved, so views can refresh.
    var version = 0

    private let manager = CLLocationManager()

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func refresh() {
        problem = nil
        switch manager.authorizationStatus {
        case .notDetermined:
            isWorking = true
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            problem = "אין הרשאת מיקום. אפשר להפעיל אותה בהגדרות האייפון, תחת שפע."
        default:
            isWorking = true
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if isWorking { manager.requestLocation() }
        case .denied, .restricted:
            if isWorking {
                isWorking = false
                problem = "בלי הרשאת מיקום נשארים עם העיר שנבחרה."
            }
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let place = locations.last else { return }
        let defaults = UserDefaults.standard
        defaults.set(place.coordinate.latitude, forKey: "deviceLatitude")
        defaults.set(place.coordinate.longitude, forKey: "deviceLongitude")
        isWorking = false
        version += 1
        CLGeocoder().reverseGeocodeLocation(place, preferredLocale: Locale(identifier: "he_IL")) { marks, _ in
            let name = marks?.first?.locality ?? marks?.first?.name
            DispatchQueue.main.async {
                if let name {
                    UserDefaults.standard.set(name, forKey: "deviceName")
                    self.version += 1
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isWorking = false
        problem = "לא הצלחנו לקבל מיקום כרגע. נסו שוב בעוד רגע."
    }
}
