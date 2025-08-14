import Foundation

class NetworkManager {
    static let shared = NetworkManager()
    
    private let baseURL = "https://food-app-swift-qb4k.onrender.com" // UPDATE THIS WITH YOUR RENDER URL
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 90
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        
        // Disable QUIC to avoid protocol issues
        config.httpMaximumConnectionsPerHost = 2
        
        return URLSession(configuration: config)
    }()
    
    private init() {}
    
    // MARK: - Token Management
    
    private var authToken: String? {
        get { UserDefaults.standard.string(forKey: "auth_token") }
        set { UserDefaults.standard.set(newValue, forKey: "auth_token") }
    }
    
    func saveToken(_ token: String) {
        authToken = token
    }
    
    func clearToken() {
        authToken = nil
    }
    
    private func createAuthenticatedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        return request
    }
    
    // MARK: - Health Check
    
    func checkHealth(completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/health") else {
            completion(false, nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Health check error: \(error)")
                    completion(false, "Network error")
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("📡 Health check status: \(httpResponse.statusCode)")
                }
                
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String {
                    completion(status == "healthy", status)
                } else {
                    completion(false, "Invalid response")
                }
            }
        }.resume()
    }
    
    // Add these methods to NetworkManager class:

    // MARK: - Cold Start Detection
    private var isFirstRequest = true
    private var coldStartDetected = false

    func checkHealthWithColdStart(completion: @escaping (Bool, String?, Bool) -> Void) {
        let startTime = Date()
        
        checkHealth { [weak self] healthy, status in
            let responseTime = Date().timeIntervalSince(startTime)
            let isColdStart = responseTime > 5.0 && (self?.isFirstRequest ?? false)
            
            self?.isFirstRequest = false
            self?.coldStartDetected = isColdStart
            
            DispatchQueue.main.async {
                completion(healthy, status, isColdStart)
            }
        }
    }

    // Enhanced upload with cold start handling
    func uploadImageWithColdStartHandling(
        imageData: Data,
        onColdStart: @escaping () -> Void,
        completion: @escaping (Result<GeminiResult, Error>) -> Void
    ) {
        // Check if we need to warm up the server first
        if isFirstRequest || coldStartDetected {
            checkHealthWithColdStart { [weak self] healthy, _, isColdStart in
                if isColdStart {
                    DispatchQueue.main.async {
                        onColdStart()
                    }
                }
                
                if healthy {
                    self?.uploadImage(imageData: imageData, completion: completion)
                } else {
                    completion(.failure(NSError(
                        domain: "NetworkManager",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Server is not responding"]
                    )))
                }
            }
        } else {
            uploadImage(imageData: imageData, completion: completion)
        }
    }
    
    // MARK: - Authentication
    
    func register(name: String, email: String, password: String, completion: @escaping (Result<(userId: String, name: String, token: String), Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/register") else {
            completion(.failure(NSError(domain: "NetworkManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = ["name": name, "email": email, "password": password]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(.failure(error))
            return
        }
        
        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let data = data else {
                    completion(.failure(NSError(domain: "NetworkManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                    return
                }
                
                do {
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    
                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                        let errorMessage = json?["error"] as? String ?? "Registration failed"
                        completion(.failure(NSError(domain: "API", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])))
                        return
                    }
                    
                    guard let userId = json?["user_id"] as? String,
                          let name = json?["name"] as? String,
                          let token = json?["token"] as? String else {
                        completion(.failure(NSError(domain: "NetworkManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])))
                        return
                    }
                    
                    self.saveToken(token)
                    completion(.success((userId, name, token)))
                    
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    func login(email: String, password: String, completion: @escaping (Result<(userId: String, name: String, token: String), Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/login") else {
            completion(.failure(NSError(domain: "NetworkManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = ["email": email, "password": password]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(.failure(error))
            return
        }
        
        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let data = data else {
                    completion(.failure(NSError(domain: "NetworkManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                    return
                }
                
                do {
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    
                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                        let errorMessage = json?["error"] as? String ?? "Login failed"
                        completion(.failure(NSError(domain: "API", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])))
                        return
                    }
                    
                    guard let userId = json?["user_id"] as? String,
                          let name = json?["name"] as? String,
                          let token = json?["token"] as? String else {
                        completion(.failure(NSError(domain: "NetworkManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])))
                        return
                    }
                    
                    self.saveToken(token)
                    completion(.success((userId, name, token)))
                    
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    // MARK: - Image Upload
    
    func uploadImage(imageData: Data, completion: @escaping (Result<GeminiResult, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/analyze") else {
            completion(.failure(NSError(domain: "NetworkManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = createAuthenticatedRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"upload.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        print("📤 Uploading image to: \(url)")
        
        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Upload error: \(error)")
                    completion(.failure(error))
                    return
                }
                
                guard let data = data else {
                    completion(.failure(NSError(domain: "NetworkManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("📡 Response status: \(httpResponse.statusCode)")
                    
                    if httpResponse.statusCode == 401 {
                        // Token expired or invalid
                        self.clearToken()
                        completion(.failure(NSError(domain: "API", code: 401, userInfo: [NSLocalizedDescriptionKey: "Authentication required. Please log in again."])))
                        return
                    }
                    
                    if httpResponse.statusCode != 200 {
                        if let responseString = String(data: data, encoding: .utf8) {
                            print("❌ Error response: \(responseString)")
                        }
                    }
                }
                
                do {
                    let result = try JSONDecoder().decode(GeminiResult.self, from: data)
                    completion(.success(result))
                } catch {
                    // Try to decode error response
                    if let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                       let errorMsg = errorDict["error"] {
                        completion(.failure(NSError(domain: "API", code: -3, userInfo: [NSLocalizedDescriptionKey: errorMsg])))
                    } else {
                        print("❌ Decode error: \(error)")
                        completion(.failure(error))
                    }
                }
            }
        }.resume()
    }
    
    // MARK: - Profile Management
    
    func saveProfile(_ profile: [String: Any], completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/save-profile") else {
            completion(false, "Invalid URL")
            return
        }
        
        var request = createAuthenticatedRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: profile)
        } catch {
            completion(false, "Failed to encode profile data")
            return
        }
        
        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, error.localizedDescription)
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 401 {
                        self.clearToken()
                        completion(false, "Authentication required. Please log in again.")
                        return
                    }
                    
                    completion(httpResponse.statusCode == 200, nil)
                } else {
                    completion(false, "No response from server")
                }
            }
        }.resume()
    }
    
    func getProfile(completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/get-profile") else {
            completion(.failure(NSError(domain: "NetworkManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        let request = createAuthenticatedRequest(url: url)
        
        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let data = data else {
                    completion(.failure(NSError(domain: "NetworkManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                    self.clearToken()
                    completion(.failure(NSError(domain: "API", code: 401, userInfo: [NSLocalizedDescriptionKey: "Authentication required"])))
                    return
                }
                
                do {
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                    completion(.success(json))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    // MARK: - Meal Operations
    
    func saveMeal(_ meal: [String: Any], completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/save-meal") else {
            completion(false, "Invalid URL")
            return
        }
        
        var request = createAuthenticatedRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: meal)
        } catch {
            completion(false, "Failed to encode meal data")
            return
        }
        
        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, error.localizedDescription)
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 401 {
                        self.clearToken()
                        completion(false, "Authentication required. Please log in again.")
                        return
                    }
                    
                    completion(httpResponse.statusCode == 200, nil)
                } else {
                    completion(false, "No response from server")
                }
            }
        }.resume()
    }
    
    func getUserMeals(completion: @escaping (Result<[Meal], Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/user-meals") else {
            completion(.failure(NSError(domain: "NetworkManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        let request = createAuthenticatedRequest(url: url)
        
        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let data = data else {
                    completion(.failure(NSError(domain: "NetworkManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                    self.clearToken()
                    completion(.failure(NSError(domain: "API", code: 401, userInfo: [NSLocalizedDescriptionKey: "Authentication required"])))
                    return
                }
                
                do {
                    let meals = try JSONDecoder().decode([Meal].self, from: data)
                    completion(.success(meals))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    func recalculateNutrition(ingredients: String, completion: @escaping (Result<NutritionRecalculationResult, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/recalculate-nutrition") else {
            completion(.failure(NSError(domain: "NetworkManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        let payload: [String: Any] = ["ingredients": ingredients]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(.failure(NSError(domain: "NetworkManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode data"])))
            return
        }
        
        var request = createAuthenticatedRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let data = data else {
                    completion(.failure(NSError(domain: "NetworkManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                    self.clearToken()
                    completion(.failure(NSError(domain: "API", code: 401, userInfo: [NSLocalizedDescriptionKey: "Authentication required"])))
                    return
                }
                
                do {
                    let result = try JSONDecoder().decode(NutritionRecalculationResult.self, from: data)
                    completion(.success(result))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    func updateMeal(mealId: String, dishName: String, ingredients: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/update-meal") else {
            completion(false)
            return
        }
        
        let payload: [String: Any] = [
            "meal_id": mealId,
            "dish_prediction": dishName,
            "image_description": ingredients
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(false)
            return
        }
        
        var request = createAuthenticatedRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        session.dataTask(with: request) { _, response, _ in
            DispatchQueue.main.async {
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 401 {
                        self.clearToken()
                    }
                    completion(http.statusCode == 200)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }
    
    func deleteMeal(mealId: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/delete-meal") else {
            completion(false)
            return
        }
        
        let payload = ["meal_id": mealId]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(false)
            return
        }
        
        var request = createAuthenticatedRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        session.dataTask(with: request) { _, response, _ in
            DispatchQueue.main.async {
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 401 {
                        self.clearToken()
                    }
                    completion(http.statusCode == 200)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }
    
    // MARK: - Health Tracking
    
    func addWater(amount: Double, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/add-water") else {
            completion(false)
            return
        }
        
        let payload: [String: Any] = [
            "amount": amount,
            "recorded_at": ISO8601DateFormatter().string(from: Date())
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(false)
            return
        }
        
        var request = createAuthenticatedRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        session.dataTask(with: request) { _, response, _ in
            DispatchQueue.main.async {
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 401 {
                        self.clearToken()
                    }
                    completion(http.statusCode == 200)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }
    
    func getWaterIntake(completion: @escaping (Result<[WaterEntry], Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/user-water") else {
            completion(.failure(NSError(domain: "NetworkManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        let request = createAuthenticatedRequest(url: url)
        
        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let data = data else {
                    completion(.failure(NSError(domain: "NetworkManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                    self.clearToken()
                    completion(.failure(NSError(domain: "API", code: 401, userInfo: [NSLocalizedDescriptionKey: "Authentication required"])))
                    return
                }
                
                do {
                    let entries = try JSONDecoder().decode([WaterEntry].self, from: data)
                    completion(.success(entries))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    func addExercise(type: String, duration: Int, intensity: String, calories: Int, notes: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/add-exercise") else {
            completion(false)
            return
        }
        
        let payload: [String: Any] = [
            "exercise_type": type,
            "duration": duration,
            "intensity": intensity,
            "calories_burned": calories,
            "notes": notes,
            "recorded_at": ISO8601DateFormatter().string(from: Date())
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(false)
            return
        }
        
        var request = createAuthenticatedRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        session.dataTask(with: request) { _, response, _ in
            DispatchQueue.main.async {
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 401 {
                        self.clearToken()
                    }
                    completion(http.statusCode == 200)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }
    
    func addWeight(weight: Double, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/add-weight") else {
            completion(false)
            return
        }
        
        let payload: [String: Any] = [
            "weight": weight,
            "recorded_at": ISO8601DateFormatter().string(from: Date())
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(false)
            return
        }
        
        var request = createAuthenticatedRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        session.dataTask(with: request) { _, response, _ in
            DispatchQueue.main.async {
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 401 {
                        self.clearToken()
                    }
                    completion(http.statusCode == 200)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }
    
    // MARK: - Logout
    
    func logout() {
        clearToken()
        // Clear any cached data
        URLCache.shared.removeAllCachedResponses()
    }
}
