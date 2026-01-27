#!/usr/bin/env swift

import CoreLocation
import Foundation

// Configuration
let BACKEND_URL = "http://35.190.202.25:8080/api/device-location"
let DEVICE_ID = "2162127"  // MacBook Air SimpleMDM ID
let REPORT_INTERVAL: TimeInterval = 60  // Report every 60 seconds

class LocationReporter: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    var lastLocation: CLLocation?
    let semaphore = DispatchSemaphore(value: 0)
    var gotLocation = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestAuthorization() {
        print("Requesting location authorization...")
        manager.requestWhenInUseAuthorization()
    }

    func startMonitoring() {
        print("Starting location updates...")
        manager.startUpdatingLocation()
    }

    func getLocationOnce(timeout: TimeInterval = 30) -> CLLocation? {
        gotLocation = false
        manager.requestLocation()

        let result = semaphore.wait(timeout: .now() + timeout)
        if result == .timedOut {
            print("Location request timed out")
            return nil
        }
        return lastLocation
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            lastLocation = loc
            gotLocation = true
            print("Location: \(loc.coordinate.latitude), \(loc.coordinate.longitude) (accuracy: \(loc.horizontalAccuracy)m)")
            semaphore.signal()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                print("Location access denied. Please enable in System Preferences > Security & Privacy > Privacy > Location Services")
            case .locationUnknown:
                print("Location unknown - try again")
            default:
                print("CLError code: \(clError.code.rawValue)")
            }
        }
        semaphore.signal()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        print("Authorization status changed: \(status.rawValue)")
        switch status {
        case .notDetermined:
            print("Status: Not determined - requesting authorization")
            requestAuthorization()
        case .restricted:
            print("Status: Restricted - location services disabled")
        case .denied:
            print("Status: Denied - enable in System Preferences")
        case .authorizedAlways, .authorizedWhenInUse:
            print("Status: Authorized")
        @unknown default:
            print("Status: Unknown")
        }
    }

    func reportLocation(_ location: CLLocation) -> Bool {
        let payload: [String: Any] = [
            "device_id": DEVICE_ID,
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "accuracy": Int(location.horizontalAccuracy),
            "altitude": location.altitude,
            "timestamp": ISO8601DateFormatter().string(from: location.timestamp)
        ]

        guard let url = URL(string: BACKEND_URL) else {
            print("Invalid backend URL")
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            print("Failed to serialize JSON: \(error)")
            return false
        }

        let reportSemaphore = DispatchSemaphore(value: 0)
        var success = false

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Failed to report: \(error.localizedDescription)")
            } else if let httpResponse = response as? HTTPURLResponse {
                print("Reported location, status: \(httpResponse.statusCode)")
                success = httpResponse.statusCode >= 200 && httpResponse.statusCode < 300
            }
            reportSemaphore.signal()
        }
        task.resume()
        _ = reportSemaphore.wait(timeout: .now() + 15)

        return success
    }

    func printLocationJSON(_ location: CLLocation) {
        let payload: [String: Any] = [
            "device_id": DEVICE_ID,
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "accuracy": Int(location.horizontalAccuracy),
            "altitude": location.altitude,
            "timestamp": ISO8601DateFormatter().string(from: location.timestamp)
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print(jsonString)
        }
    }
}

// Main
let args = CommandLine.arguments
let reporter = LocationReporter()

// Check authorization first
let status = CLLocationManager.authorizationStatus()
print("Initial authorization status: \(status.rawValue)")

if status == .notDetermined {
    print("\nLocation permission not yet granted.")
    print("This app needs location access to report device location.")
    print("Please grant permission when prompted.\n")
    reporter.requestAuthorization()
    // Wait a moment for authorization dialog
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 3))
}

if args.contains("--daemon") {
    // Daemon mode - keep running and report periodically
    print("\nRunning in daemon mode (reporting every \(Int(REPORT_INTERVAL))s)")
    print("Backend: \(BACKEND_URL)")
    print("Device ID: \(DEVICE_ID)\n")

    reporter.startMonitoring()

    while true {
        if let location = reporter.lastLocation {
            if reporter.reportLocation(location) {
                print("Successfully reported location")
            }
        } else {
            print("Waiting for location...")
        }
        Thread.sleep(forTimeInterval: REPORT_INTERVAL)
    }
} else if args.contains("--report") {
    // Single report mode
    print("Getting location and reporting to backend...")
    if let location = reporter.getLocationOnce() {
        if reporter.reportLocation(location) {
            print("Successfully reported location to backend")
        } else {
            print("Failed to report location")
            exit(1)
        }
    } else {
        print("Failed to get location")
        exit(1)
    }
} else if args.contains("--json") {
    // JSON output mode
    if let location = reporter.getLocationOnce() {
        reporter.printLocationJSON(location)
    } else {
        print("{\"error\": \"Failed to get location\"}")
        exit(1)
    }
} else {
    // Default - just print location
    print("Getting current location...")
    if let location = reporter.getLocationOnce() {
        print("\nLocation:")
        print("  Latitude:  \(location.coordinate.latitude)")
        print("  Longitude: \(location.coordinate.longitude)")
        print("  Accuracy:  \(location.horizontalAccuracy)m")
        print("  Altitude:  \(location.altitude)m")
        print("  Timestamp: \(location.timestamp)")
        print("\nUsage:")
        print("  --report  Report location to backend")
        print("  --daemon  Run continuously, reporting every \(Int(REPORT_INTERVAL))s")
        print("  --json    Output location as JSON")
    } else {
        print("Failed to get location")
        print("\nMake sure location services are enabled:")
        print("  System Preferences > Security & Privacy > Privacy > Location Services")
        exit(1)
    }
}
