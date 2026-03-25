//Sign-Up Screen/Sign-In Screen

struct User: Codable {
    let name: String
    let email: String
    let password: String
}

class UserManager {
    static let shared = UserManager()
    private let userKey = "savedUser"
    
    func save(user: User) {
        if let encoded = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(encoded, forKey: userKey)
        }
    }
    
    func validate(email: String, password: String) -> Bool {
        guard let saved = getUser() else { return false }
        return saved.email == email && saved.password == password
    }
}


//Biometric Authentication Implementation

import LocalAuthentication

class BiometricManager {
    static let shared = BiometricManager()
    private let context = LAContext()
    private let biometricRegisteredKey = "biometricRegistered"
    
    func isBiometricAvailable() -> Bool {
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    func registerBiometric(completion: @escaping (Bool, String?) -> Void) {
        guard isBiometricAvailable() else {
            completion(false, "Biometric not available on this device")
            return
        }
        
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                               localizedReason: "Register your biometric for attendance") { success, error in
            DispatchQueue.main.async {
                if success {
                    UserDefaults.standard.set(true, forKey: self.biometricRegisteredKey)
                    completion(true, nil)
                } else {
                    completion(false, error?.localizedDescription ?? "Authentication failed")
                }
            }
        }
    }
    
    func authenticateBiometric(completion: @escaping (Bool, String?) -> Void) {
        guard UserDefaults.standard.bool(forKey: biometricRegisteredKey) else {
            completion(false, "No biometric registered. Please register first.")
            return
        }
        
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                               localizedReason: "Authenticate to mark attendance") { success, error in
            DispatchQueue.main.async {
                if success {
                    completion(true, nil)
                } else {
                    completion(false, error?.localizedDescription ?? "Authentication failed")
                }
            }
        }
    }
}

//GPS Location Verification

import CoreLocation

class LocationManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    private let locationManager = CLLocationManager()
    private var completion: ((Bool) -> Void)?
    
    // Example office location (Apple HQ coordinates)
    private let officeLocation = CLLocation(latitude: 37.3317, longitude: -122.0302)
    private let officeRadius: Double = 100.0 // meters
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func verifyOfficeLocation(completion: @escaping (Bool) -> Void) {
        self.completion = completion
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let userLocation = locations.last else {
            completion?(false)
            return
        }
        
        let distance = userLocation.distance(from: officeLocation)
        completion?(distance <= officeRadius)
        locationManager.stopUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        completion?(false)
        locationManager.stopUpdatingLocation()
    }
}

//Check-In/Check-Out Logic

class AttendanceManager {
    static let shared = AttendanceManager()
    private let userDefaults = UserDefaults.standard
    
    func canCheckIn(for email: String) -> Bool {
        let key = "\(email)_lastCheckIn"
        guard let lastCheckIn = userDefaults.object(forKey: key) as? Date else {
            return true
        }
        return !Calendar.current.isDateInToday(lastCheckIn)
    }
    
    func canCheckOut(for email: String) -> Bool {
        let key = "\(email)_lastCheckOut"
        guard let lastCheckOut = userDefaults.object(forKey: key) as? Date else {
            return true
        }
        return !Calendar.current.isDateInToday(lastCheckOut)
    }
    
    func recordCheckIn(for email: String) {
        let key = "\(email)_lastCheckIn"
        userDefaults.set(Date(), forKey: key)
        userDefaults.set("Check-In", forKey: "\(email)_lastAction")
    }
    
    func recordCheckOut(for email: String) {
        let key = "\(email)_lastCheckOut"
        userDefaults.set(Date(), forKey: key)
        userDefaults.set("Check-Out", forKey: "\(email)_lastAction")
    }
}

//Network Error Enumeration

enum NetworkError: Error {
    case noInternet
    case noData
    case invalidResponse
    case decodingFailed
    case httpError(statusCode: Int)
    
    var userFriendlyMessage: String {
        switch self {
        case .noInternet:
            return "No internet connection. Please check your network settings."
        case .noData:
            return "No data received from server."
        case .invalidResponse:
            return "Invalid server response."
        case .decodingFailed:
            return "Failed to process server data."
        case .httpError(let code):
            return "Server error (HTTP \(code)). Please try again later."
        }
    }
}

//Generic Network Manager

class NetworkManager {
    static let shared = NetworkManager()
    
    func fetchData<T: Decodable>(from url: URL,
                                 type: T.Type,
                                 completion: @escaping (Result<T, NetworkError>) -> Void) {
        
        // Check internet connectivity
        guard isInternetAvailable() else {
            completion(.failure(.noInternet))
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            // Handle network error
            if let error = error {
                print("Network error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(.noInternet))
                }
                return
            }
            
            // Validate HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    completion(.failure(.invalidResponse))
                }
                return
            }
            
            // Check HTTP status code
            guard (200...299).contains(httpResponse.statusCode) else {
                DispatchQueue.main.async {
                    completion(.failure(.httpError(statusCode: httpResponse.statusCode)))
                }
                return
            }
            
            // Validate data presence
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(.noData))
                }
                return
            }
            
            // Decode response
            do {
                let decodedData = try JSONDecoder().decode(T.self, from: data)
                DispatchQueue.main.async {
                    completion(.success(decodedData))
                }
            } catch {
                print("Decoding error: \(error)")
                DispatchQueue.main.async {
                    completion(.failure(.decodingFailed))
                }
            }
        }
        
        task.resume()
    }
    
    private func isInternetAvailable() -> Bool {
        // Implementation using NWPathMonitor or Reachability
        return true // Simplified for example
    }
}

//Demo: Fetching Data from Dummy API

struct Todo: Codable {
    let id: Int
    let title: String
    let completed: Bool
}

// In HomeViewController
@IBAction func fetchDataTapped(_ sender: UIButton) {
    guard let url = URL(string: "https://jsonplaceholder.typicode.com/todos/1") else {
        return
    }
    
    NetworkManager.shared.fetchData(from: url, type: Todo.self) { result in
        switch result {
        case .success(let todo):
            self.showAlert(title: "Success",
                          message: "Fetched: \(todo.title)")
        case .failure(let error):
            self.showAlert(title: "Error",
                          message: error.userFriendlyMessage)
        }
    }
}

//Authentication Errors

enum AuthError: Error {
    case invalidEmail
    case emptyFields
    case credentialsMismatch
    case userNotFound
    
    var message: String {
        switch self {
        case .invalidEmail:
            return "Please enter a valid email address"
        case .emptyFields:
            return "All fields are required"
        case .credentialsMismatch:
            return "Invalid email or password"
        case .userNotFound:
            return "No account found with this email"
        }
    }
}

func validateSignUp(name: String, email: String, password: String) -> Result<User, AuthError> {
    guard !name.isEmpty, !email.isEmpty, !password.isEmpty else {
        return .failure(.emptyFields)
    }
    
    guard isValidEmail(email) else {
        return .failure(.invalidEmail)
    }
    
    return .success(User(name: name, email: email, password: password))
}

private func isValidEmail(_ email: String) -> Bool {
    let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
    let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
    return emailPredicate.evaluate(with: email)
}

//Biometric Authentication Error Handling

enum BiometricError: Error {
    case notAvailable
    case notRegistered
    case authenticationFailed(reason: String)
    case userCancel
    case systemCancel
    
    var message: String {
        switch self {
        case .notAvailable:
            return "Biometric authentication is not available on this device"
        case .notRegistered:
            return "Please register your biometric first"
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .userCancel:
            return "Authentication cancelled"
        case .systemCancel:
            return "System cancelled authentication"
        }
    }
}

//Attendance Logic Error Handling

enum AttendanceError: Error {
    case alreadyCheckedIn
    case alreadyCheckedOut
    case locationMismatch
    case biometricMismatch
    
    var message: String {
        switch self {
        case .alreadyCheckedIn:
            return "You have already checked in today"
        case .alreadyCheckedOut:
            return "You have already checked out today"
        case .locationMismatch:
            return "You are not at the office location"
        case .biometricMismatch:
            return "Biometric verification failed"
        }
    }
}

//Complete Check-In Flow with Error Handling

@IBAction func checkInTapped(_ sender: UIButton) {
    let email = UserManager.shared.getUser()?.email ?? ""
    
    // Case 3: Already checked in today
    guard AttendanceManager.shared.canCheckIn(for: email) else {
        showError(AttendanceError.alreadyCheckedIn)
        return
    }
    
    // Case 1 & 2: Biometric check
    BiometricManager.shared.authenticateBiometric { success, errorMessage in
        if !success {
            if let message = errorMessage {
                // Show biometric registration prompt if needed
                if message.contains("No biometric registered") {
                    self.promptBiometricRegistration()
                } else {
                    self.showError(BiometricError.authenticationFailed(reason: message))
                }
            }
            return
        }
        
        // Case 2a: Verify location
        LocationManager.shared.verifyOfficeLocation { isAtOffice in
            guard isAtOffice else {
                self.showError(AttendanceError.locationMismatch)
                return
            }
            
            // Record successful check-in
            AttendanceManager.shared.recordCheckIn(for: email)
            self.showSuccess(message: "Check-In successful at \(Date())")
        }
    }
}