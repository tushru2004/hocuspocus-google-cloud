#!/usr/bin/env swift

import CoreLocation
import Foundation

// Configuration
// We use a dummy domain that routes through the VPN. 
// The proxy intercepts the /__track_location__ path.
let BACKEND_URL = "http://google.com/__track_location__"
let DEVICE_ID = "2162127"  // MacBook Air SimpleMDM ID
let REPORT_INTERVAL: TimeInterval = 30  // Report every 30 seconds

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
        manager.requestAlwaysAuthorization() 
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
            // print("Location: \(loc.coordinate.latitude), \(loc.coordinate.longitude) (accuracy: \(loc.horizontalAccuracy)m)")
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
            "timestamp": ISO8601DateFormatter().string(from: location.timestamp),
            "url": "macos-location-reporter"
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
                // print("Reported location, status: \(httpResponse.statusCode)")
                success = httpResponse.statusCode >= 200 && httpResponse.statusCode < 300
                
                // Check if blocked
                if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let blocked = json["blocked"] as? Bool, blocked {
                    print("⚠️  AT BLOCKED LOCATION!")
                } else {
                     print("✅  Location reported (lat: \(String(format: "%.4f", location.coordinate.latitude)), lng: \(String(format: "%.4f", location.coordinate.longitude)))")
                }
            }
            reportSemaphore.signal()
        }
        task.resume()
        _ = reportSemaphore.wait(timeout: .now() + 15)

        return success
    }
}

// Main
let args = CommandLine.arguments
let reporter = LocationReporter()

// Check authorization first
let status = CLLocationManager.authorizationStatus()
if status == .notDetermined {
    print("Requesting location authorization...")
    reporter.requestAuthorization()
    // Wait for prompt interaction
    print("Please allow location access in the dialog...")
    sleep(5) 
}

print("Starting location reporter (Device ID: \(DEVICE_ID))...")
print("Press Ctrl+C to stop.")

reporter.startMonitoring()

while true {
    if let location = reporter.lastLocation {
        _ = reporter.reportLocation(location)
    } else {
        print("Waiting for location fix...")
    }
    Thread.sleep(forTimeInterval: REPORT_INTERVAL)
}
