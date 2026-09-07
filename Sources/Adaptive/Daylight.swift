import CoreLocation
import Foundation
import Observation

/// Where sunrise and sunset come from. Off, every day runs 7 to 19. On, one
/// approximate fix from Core Location (a tenth of a degree, ten kilometres,
/// which moves sunrise by half a minute) is kept in defaults, and the sun is
/// computed from it: no network, and the fix is refreshed once per launch.
/// The system asks for permission the first time the switch goes on, which
/// is the one moment the user is looking at why.
@MainActor
@Observable
final class Daylight {
    static let shared = Daylight(defaults: .standard)

    var followsLocation: Bool {
        didSet {
            defaults.set(followsLocation, forKey: "daylight.location")
            followsLocation ? locate() : fetch?.cancel()
            onChange?()
        }
    }
    /// The user declined location; only Settings can turn it back on.
    private(set) var denied = false
    /// Called when the day model changed: the switch, or a fix arriving.
    var onChange: (@MainActor () -> Void)?

    private var coordinate: (latitude: Double, longitude: Double)? {
        didSet {
            defaults.set(coordinate?.latitude, forKey: "daylight.latitude")
            defaults.set(coordinate?.longitude, forKey: "daylight.longitude")
        }
    }
    private let defaults: UserDefaults
    private var fetch: Task<Void, Never>?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        followsLocation = defaults.bool(forKey: "daylight.location")
        if let latitude = defaults.object(forKey: "daylight.latitude") as? Double,
           let longitude = defaults.object(forKey: "daylight.longitude") as? Double {
            coordinate = (latitude, longitude)
        }
        if followsLocation { locate() }
    }

    /// The sun on the calendar day holding `date`.
    func day(on date: Date) -> SolarDay {
        guard followsLocation, let coordinate else { return .clock(on: date) }
        return .solar(latitude: coordinate.latitude, longitude: coordinate.longitude, on: date)
    }

    /// One fix, then the stream is closed. Reduced accuracy is all the
    /// Info.plist asks for, so the prompt offers the approximate option only.
    /// A refusal keeps the stream open: it costs nothing while denied, and
    /// it is what delivers the fix once the user allows it in Settings.
    private func locate() {
        fetch?.cancel()
        fetch = Task {
            // Live updates ask for when-in-use authorization themselves the
            // first time; the reduced-accuracy key limits what they ask for.
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    guard !Task.isCancelled else { return }
                    if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                        if !denied {
                            denied = true
                            onChange?()
                        }
                        continue
                    }
                    guard let location = update.location else { continue }
                    denied = false
                    let latitude = (location.coordinate.latitude * 10).rounded() / 10
                    let longitude = (location.coordinate.longitude * 10).rounded() / 10
                    if coordinate?.latitude != latitude || coordinate?.longitude != longitude {
                        coordinate = (latitude, longitude)
                        onChange?()
                    }
                    return
                }
            } catch {
                // No fix: the clock day stands in until the next launch.
            }
        }
    }
}
