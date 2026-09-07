import Foundation

/// Sunrise and sunset on one calendar day, computed on the device. No
/// network: the sun's position is arithmetic on the date and a coordinate.
struct SolarDay: Equatable, Sendable {
    var sunrise: Date
    var sunset: Date

    /// The day's daylight has to be long enough to hold the morning arc and
    /// short enough to leave a night, so the polar cases clamp here: a
    /// midwinter Tromsø day is treated as four hours around solar noon, a
    /// midsummer one as twenty.
    static let shortestDay: TimeInterval = 4 * 3600
    static let longestDay: TimeInterval = 20 * 3600

    /// The sun at `latitude`, `longitude` (degrees, north and east positive)
    /// on the calendar day holding `date`. Meeus' low-precision solar
    /// position via the NOAA sunrise equation, within a minute or two of
    /// the almanac, which is all a sound needs. Sunrise is the upper limb at
    /// the horizon with standard refraction, -0.833°.
    static func solar(latitude: Double, longitude: Double, on date: Date, calendar: Calendar = .current) -> SolarDay {
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        let julian = noon.timeIntervalSince1970 / 86400 + 2440587.5
        let days = (julian - 2451545.0).rounded()
        let radians = Double.pi / 180

        let meanSolarTime = days - longitude / 360
        let anomaly = (357.5291 + 0.98560028 * meanSolarTime).truncatingRemainder(dividingBy: 360)
        let center = 1.9148 * sin(anomaly * radians) + 0.02 * sin(2 * anomaly * radians) + 0.0003 * sin(3 * anomaly * radians)
        let eclipticLongitude = (anomaly + center + 180 + 102.9372).truncatingRemainder(dividingBy: 360)
        let transit = 2451545.0 + meanSolarTime + 0.0053 * sin(anomaly * radians) - 0.0069 * sin(2 * eclipticLongitude * radians)
        let declination = asin(sin(eclipticLongitude * radians) * sin(23.4397 * radians))
        let cosHourAngle = (sin(-0.833 * radians) - sin(latitude * radians) * sin(declination))
            / (cos(latitude * radians) * cos(declination))
        // Above 1 the sun never rises, below -1 it never sets; both land on
        // the clamp.
        let hourAngle = acos(min(1, max(-1, cosHourAngle))) / radians
        let halfDay = min(longestDay, max(shortestDay, hourAngle / 360 * 2 * 86400)) / 2

        let transitDate = Date(timeIntervalSince1970: (transit - 2440587.5) * 86400)
        return SolarDay(sunrise: transitDate.addingTimeInterval(-halfDay), sunset: transitDate.addingTimeInterval(halfDay))
    }

    /// Without a location: a clock day from 7 to 19, the same every season.
    static func clock(on date: Date, calendar: Calendar = .current) -> SolarDay {
        SolarDay(
            sunrise: calendar.date(bySettingHour: 7, minute: 0, second: 0, of: date) ?? date,
            sunset: calendar.date(bySettingHour: 19, minute: 0, second: 0, of: date) ?? date
        )
    }
}
