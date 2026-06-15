import Foundation

// MARK: - Timeout constants
private enum NMTimeout {
    static let health:   TimeInterval = 10   // /ping /health
    static let short:    TimeInterval = 15   // lightweight reads
    static let standard: TimeInterval = 30   // normal reads/writes
    static let login:    TimeInterval = 90   // /login – must survive cold start
    static let upload:   TimeInterval = 120  // Gemini image analysis
}

class NetworkManager {
    static let shared = NetworkManager()

    private let baseURL = AppConfig.apiBaseURL

    // General session – most endpoints
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = NMTimeout.standard
        config.timeoutIntervalForResource = NMTimeout.upload
        config.waitsForConnectivity       = true
        config.allowsCellularAccess       = true
        config.httpMaximumConnectionsPerHost = 2
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: config)
    }()

    // Long-lived session – login / Gemini calls
    private lazy var fastSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = NMTimeout.login
        config.timeoutIntervalForResource = NMTimeout.upload
        config.waitsForConnectivity       = true
        config.allowsCellularAccess       = true
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - Token Management

    private var authToken: String? {
        get { UserDefaults.standard.string(forKey: "auth_token") }
        set { UserDefaults.standard.set(newValue, forKey: "auth_token") }
    }

    func saveToken(_ token: String) { authToken = token }
    func clearToken()               { authToken = nil  }

    private func createAuthenticatedRequest(url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.timeoutInterval  = NMTimeout.standard
        req.cachePolicy      = .reloadIgnoringLocalAndRemoteCacheData
        if let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    // MARK: - Health Check

    func checkHealth(completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/health") else { completion(false, nil); return }
        var req = URLRequest(url: url)
        req.timeoutInterval = NMTimeout.health
        req.cachePolicy     = .reloadIgnoringLocalAndRemoteCacheData
        session.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { completion(false, "Network error: \(error.localizedDescription)"); return }
                if let data = data,
                   let json   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String {
                    completion(status == "healthy", status)
                } else {
                    completion(false, "Invalid response")
                }
            }
        }.resume()
    }

    // MARK: - Server Warm-Up (fire-and-forget ping, no longer blocks login)

    func warmUpServer(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/ping") else { completion(false); return }
        var req = URLRequest(url: url)
        req.timeoutInterval = NMTimeout.login   // 90s – give cold-start enough time
        print("🔥 Warming up server…")
        URLSession.shared.dataTask(with: req) { _, response, _ in
            DispatchQueue.main.async {
                let ok = (response as? HTTPURLResponse)?.statusCode == 200
                print(ok ? "✅ Server warmed up!" : "⚠️ Server warm-up uncertain")
                completion(ok)
            }
        }.resume()
    }

    // MARK: - Cold Start Detection

    private var isFirstRequest  = true
    private var coldStartDetected = false

    func checkHealthWithColdStart(completion: @escaping (Bool, String?, Bool) -> Void) {
        let start = Date()
        checkHealth { [weak self] healthy, status in
            let isColdStart = Date().timeIntervalSince(start) > 5.0 && (self?.isFirstRequest ?? false)
            self?.isFirstRequest     = false
            self?.coldStartDetected  = isColdStart
            completion(healthy, status, isColdStart)
        }
    }

    func uploadImageWithColdStartHandling(
        imageData: Data,
        onColdStart: @escaping () -> Void,
        completion: @escaping (Result<GeminiResult, Error>) -> Void
    ) {
        if isFirstRequest || coldStartDetected {
            checkHealthWithColdStart { [weak self] healthy, _, isColdStart in
                if isColdStart { DispatchQueue.main.async { onColdStart() } }
                if healthy { self?.uploadImage(imageData: imageData, completion: completion) }
                else {
                    completion(.failure(NSError(domain: "NetworkManager", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Server is not responding"])))
                }
            }
        } else {
            uploadImage(imageData: imageData, completion: completion)
        }
    }

    // MARK: - Authentication

    func register(name: String, email: String, password: String,
                  completion: @escaping (Result<(userId: String, name: String, token: String), Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/register") else {
            completion(.failure(nsErr(-1, "Invalid URL"))); return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["name": name, "email": email, "password": password])
        session.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)); return }
                guard let data = data else { completion(.failure(self.nsErr(-2, "No data"))); return }
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    completion(.failure(self.nsErr(http.statusCode, json?["error"] as? String ?? "Registration failed"))); return
                }
                guard let userId = json?["user_id"] as? String,
                      let name   = json?["name"]    as? String,
                      let token  = json?["token"]   as? String
                else { completion(.failure(self.nsErr(-3, "Invalid response"))); return }
                self.saveToken(token)
                completion(.success((userId, name, token)))
            }
        }.resume()
    }

    // Standard (non-fast) login – kept for backward compat
    func login(email: String, password: String,
               completion: @escaping (Result<(userId: String, name: String, token: String), Error>) -> Void) {
        loginFast(email: email, password: password, completion: completion)
    }

    // MARK: - loginFast  ← KEY FIX
    //
    // Old behaviour: warmUpServer (up to 90 s) → performLogin (up to 60 s) = up to 150 s serial
    // New behaviour: fire /ping AND /login at the same time.
    //   • If /login succeeds first  → use its result, ignore the ping
    //   • If /ping returns first    → wait for login (login gets 90 s total)
    //   • Once either path resolves, guard ensures completion fires exactly once.

    func loginFast(email: String, password: String,
                   completion: @escaping (Result<(userId: String, name: String, token: String), Error>) -> Void) {
        print("🚀 loginFast initiated for: \(email)")
        let lock      = NSLock()
        var done      = false          // guards single-fire of completion
        var loginDone = false          // did /login already return?
        var pingDone  = false          // did /ping already return?
        var loginResult: Result<(userId: String, name: String, token: String), Error>?

        // Helper – call completion exactly once
        func finish(_ result: Result<(userId: String, name: String, token: String), Error>) {
            lock.lock(); defer { lock.unlock() }
            guard !done else { return }
            done = true
            DispatchQueue.main.async { completion(result) }
        }

        // 1. Fire /ping in parallel (warms up the server but does NOT gate login)
        warmUpServer { _ in
            lock.lock()
            pingDone = true
            let pendingResult = loginResult
            let alreadyDone   = done
            lock.unlock()

            // If login already returned with success, nothing to do.
            // If login already returned with failure, also nothing to do – finish() already fired.
            // If login hasn't returned yet, the ping just finished first; login will call finish() when ready.
            _ = (pendingResult, pingDone, alreadyDone)  // suppress warnings
        }

        // 2. Fire /login immediately – do NOT wait for ping
        performLogin(email: email, password: password) { result in
            lock.lock()
            loginDone    = true
            loginResult  = result
            lock.unlock()
            finish(result)
        }

        _ = loginDone   // suppress unused-var warning
    }

    private func performLogin(email: String, password: String,
                              completion: @escaping (Result<(userId: String, name: String, token: String), Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/login") else {
            completion(.failure(nsErr(-1, "Invalid URL"))); return
        }
        var req = URLRequest(url: url)
        req.httpMethod      = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = NMTimeout.login   // 90 s – enough for cold start
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email, "password": password])

        let start = Date()
        fastSession.dataTask(with: req) { data, response, error in
            let duration = Date().timeIntervalSince(start)
            print("⏱️ Login completed in \(String(format: "%.2f", duration))s")
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)); return }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { completion(.failure(self.nsErr(-3, "No data"))); return }
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    completion(.failure(self.nsErr(http.statusCode, json["error"] as? String ?? "Login failed"))); return
                }
                guard let userId = json["user_id"] as? String,
                      let name   = json["name"]    as? String,
                      let token  = json["token"]   as? String
                else { completion(.failure(self.nsErr(-4, "Invalid response"))); return }
                self.saveToken(token)
                print("✅ Login successful!")
                completion(.success((userId, name, token)))
            }
        }.resume()
    }

    // MARK: - Apple Login  ← timeout fixed 15→90s

    func appleLogin(email: String, identityToken: String,
                    completion: @escaping (Result<(userId: String, name: String, token: String), Error>) -> Void) {
        print("🍎 Apple login initiated for: \(email)")
        guard let url = URL(string: "\(baseURL)/apple_login") else {
            completion(.failure(nsErr(-1, "Invalid URL"))); return
        }
        var req = URLRequest(url: url)
        req.httpMethod      = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = NMTimeout.login   // was 15 s – far too short for cold start
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email, "identityToken": identityToken])

        fastSession.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)); return }
                guard let data = data else { completion(.failure(self.nsErr(-2, "No data"))); return }
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    completion(.failure(self.nsErr(http.statusCode, json?["error"] as? String ?? "Apple login failed"))); return
                }
                guard let userId = json?["user_id"] as? String,
                      let name   = json?["name"]    as? String,
                      let token  = json?["token"]   as? String
                else { completion(.failure(self.nsErr(-3, "Invalid response format"))); return }
                self.saveToken(token)
                completion(.success((userId, name, token)))
            }
        }.resume()
    }

    // MARK: - Other Auth

    func getLoginMethods(completion: @escaping (Result<[String], Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/get-login-methods") else {
            completion(.failure(nsErr(-1, "Invalid URL"))); return
        }
        var req = createAuthenticatedRequest(url: url)
        req.httpMethod = "GET"
        session.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)); return }
                guard let data = data else { completion(.failure(self.nsErr(-2, "No data"))); return }
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 401 { self.clearToken(); completion(.failure(self.nsErr(401, "Auth required"))); return }
                    if http.statusCode != 200 { completion(.failure(self.nsErr(http.statusCode, "Failed"))); return }
                }
                let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let methods = json?["login_methods"] as? [String] ?? []
                completion(.success(methods))
            }
        }.resume()
    }

    func linkEmailPassword(password: String, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/link-email-password") else { completion(false, "Invalid URL"); return }
        var req = createAuthenticatedRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["password": password])
        session.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { completion(false, error.localizedDescription); return }
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 401 { self.clearToken(); completion(false, "Auth required"); return }
                    if http.statusCode == 200 { completion(true, nil); return }
                    let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                    completion(false, json?["error"] as? String ?? "Failed")
                } else { completion(false, "Unknown error") }
            }
        }.resume()
    }

    // MARK: - Image Upload

    func uploadImage(imageData: Data, completion: @escaping (Result<GeminiResult, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/analyze") else {
            completion(.failure(nsErr(-1, "Invalid URL"))); return
        }
        var req = createAuthenticatedRequest(url: url)
        req.httpMethod      = "POST"
        req.timeoutInterval = NMTimeout.upload
        req.cachePolicy     = .reloadIgnoringLocalAndRemoteCacheData

        let boundary = UUID().uuidString
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"upload.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        session.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)); return }
                guard let data = data else { completion(.failure(self.nsErr(-2, "No data"))); return }
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 401 { self.clearToken(); completion(.failure(self.nsErr(401, "Auth required"))); return }
                }
                do {
                    completion(.success(try JSONDecoder().decode(GeminiResult.self, from: data)))
                } catch {
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: String]
                    completion(.failure(self.nsErr(-3, json?["error"] ?? error.localizedDescription)))
                }
            }
        }.resume()
    }

    // MARK: - Profile

    func saveProfile(_ profile: [String: Any], completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/save-profile") else { completion(false, "Invalid URL"); return }
        var req = createAuthenticatedRequest(url: url)
        req.httpMethod = "POST"; req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: profile)
        session.dataTask(with: req) { _, response, error in
            DispatchQueue.main.async {
                if let error = error { completion(false, error.localizedDescription); return }
                guard let http = response as? HTTPURLResponse else { completion(false, "No response"); return }
                if http.statusCode == 401 { self.clearToken(); completion(false, "Auth required"); return }
                completion(http.statusCode == 200, nil)
            }
        }.resume()
    }

    func getProfile(completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/get-profile") else {
            completion(.failure(nsErr(-1, "Invalid URL"))); return
        }
        session.dataTask(with: createAuthenticatedRequest(url: url)) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)); return }
                guard let data = data else { completion(.failure(self.nsErr(-2, "No data"))); return }
                if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                    self.clearToken(); completion(.failure(self.nsErr(401, "Auth required"))); return
                }
                let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
                completion(.success(json))
            }
        }.resume()
    }

    // MARK: - Meals

    func saveMeal(_ meal: [String: Any], completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/save-meal") else { completion(false, "Invalid URL"); return }
        var req = createAuthenticatedRequest(url: url)
        req.httpMethod = "POST"; req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: meal)
        session.dataTask(with: req) { _, response, error in
            DispatchQueue.main.async {
                if let error = error { completion(false, error.localizedDescription); return }
                guard let http = response as? HTTPURLResponse else { completion(false, "No response"); return }
                if http.statusCode == 401 { self.clearToken(); completion(false, "Auth required"); return }
                completion(http.statusCode == 200, nil)
            }
        }.resume()
    }

    func getUserMeals(completion: @escaping (Result<[Meal], Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/user-meals") else {
            completion(.failure(nsErr(-1, "Invalid URL"))); return
        }
        session.dataTask(with: createAuthenticatedRequest(url: url)) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)); return }
                guard let data = data else { completion(.failure(self.nsErr(-2, "No data"))); return }
                if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                    self.clearToken(); completion(.failure(self.nsErr(401, "Auth required"))); return
                }
                do { completion(.success(try JSONDecoder().decode([Meal].self, from: data))) }
                catch { completion(.failure(error)) }
            }
        }.resume()
    }

    func recalculateNutrition(ingredients: String, completion: @escaping (Result<NutritionRecalculationResult, Error>) -> Void) {
        recalculateNutritionBackground(ingredients: ingredients, completion: completion)
    }

    func recalculateNutritionBackground(ingredients: String, completion: @escaping (Result<NutritionRecalculationResult, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/recalculate-nutrition") else {
            completion(.failure(nsErr(-1, "Invalid URL"))); return
        }
        var req = createAuthenticatedRequest(url: url)
        req.httpMethod = "POST"; req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = NMTimeout.upload
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["ingredients": ingredients])
        fastSession.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)); return }
                guard let data = data else { completion(.failure(self.nsErr(-3, "No data"))); return }
                if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                    self.clearToken(); completion(.failure(self.nsErr(401, "Auth required"))); return
                }
                do { completion(.success(try JSONDecoder().decode(NutritionRecalculationResult.self, from: data))) }
                catch { completion(.failure(error)) }
            }
        }.resume()
    }

    func updateMeal(mealId: String, dishName: String, ingredients: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/update-meal") else { completion(false); return }
        var req = createAuthenticatedRequest(url: url)
        req.httpMethod = "PUT"; req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["meal_id": mealId, "dish_prediction": dishName, "image_description": ingredients])
        session.dataTask(with: req) { _, response, _ in
            DispatchQueue.main.async {
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 401 { self.clearToken() }
                    completion(http.statusCode == 200)
                } else { completion(false) }
            }
        }.resume()
    }

    func deleteMeal(mealId: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/delete-meal") else { completion(false); return }
        var req = createAuthenticatedRequest(url: url)
        req.httpMethod = "DELETE"; req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["meal_id": mealId])
        session.dataTask(with: req) { _, response, _ in
            DispatchQueue.main.async {
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 401 { self.clearToken() }
                    completion(http.statusCode == 200)
                } else { completion(false) }
            }
        }.resume()
    }

    // MARK: - Health Tracking

    func addWater(amount: Double, completion: @escaping (Bool) -> Void) {
        post("\(baseURL)/add-water",
             payload: ["amount": amount, "recorded_at": ISO8601DateFormatter().string(from: Date())],
             completion: completion)
    }

    func getWaterIntake(completion: @escaping (Result<[WaterEntry], Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/user-water") else {
            completion(.failure(nsErr(-1, "Invalid URL"))); return
        }
        session.dataTask(with: createAuthenticatedRequest(url: url)) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)); return }
                guard let data = data else { completion(.failure(self.nsErr(-2, "No data"))); return }
                if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                    self.clearToken(); completion(.failure(self.nsErr(401, "Auth required"))); return
                }
                do { completion(.success(try JSONDecoder().decode([WaterEntry].self, from: data))) }
                catch { completion(.failure(error)) }
            }
        }.resume()
    }

    func addExercise(type: String, duration: Int, intensity: String, calories: Int, notes: String, completion: @escaping (Bool) -> Void) {
        post("\(baseURL)/add-exercise", payload: [
            "exercise_type": type, "duration": duration, "intensity": intensity,
            "calories_burned": calories, "notes": notes,
            "recorded_at": ISO8601DateFormatter().string(from: Date())
        ], completion: completion)
    }

    func addWeight(weight: Double, completion: @escaping (Bool) -> Void) {
        post("\(baseURL)/add-weight",
             payload: ["weight": weight, "recorded_at": ISO8601DateFormatter().string(from: Date())],
             completion: completion)
    }

    // MARK: - Logout

    func logout() {
        clearToken()
        URLCache.shared.removeAllCachedResponses()
    }

    // MARK: - Private helpers

    private func post(_ urlString: String, payload: [String: Any], completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: urlString) else { completion(false); return }
        var req = createAuthenticatedRequest(url: url)
        req.httpMethod = "POST"; req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        session.dataTask(with: req) { _, response, _ in
            DispatchQueue.main.async {
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 401 { self.clearToken() }
                    completion(http.statusCode == 200)
                } else { completion(false) }
            }
        }.resume()
    }

    private func nsErr(_ code: Int, _ msg: String) -> NSError {
        NSError(domain: "NetworkManager", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
    }
}
