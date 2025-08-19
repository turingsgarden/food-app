# 📸 NutriCam - AI-Powered Nutrition Tracker

<div align="center">
  <img src="https://github.com/yourusername/nutrisnap/blob/main/assets/nutrisnap-logo.png" alt="NutriSnap Logo" width="200" height="200">
  
  <p align="center">
    <strong>Your Personal AI Nutritionist in Your Pocket!</strong>
  </p>
  
  [![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
  [![iOS](https://img.shields.io/badge/iOS-17.0+-blue.svg)](https://www.apple.com/ios/)
  [![Python](https://img.shields.io/badge/Python-3.9+-green.svg)](https://www.python.org)
  [![License](https://img.shields.io/badge/License-MIT-purple.svg)](LICENSE)
  [![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)
  
  <p align="center">
    <a href="#✨-features">Features</a> •
    <a href="#📱-screenshots">Screenshots</a> •
    <a href="#🚀-quick-start">Quick Start</a> •
    <a href="#🛠-tech-stack">Tech Stack</a> •
    <a href="#📲-installation">Installation</a> •
    <a href="#🌐-deployment">Deployment</a>
  </p>
</div>

---

## 🎯 Overview

**NutriCam** revolutionizes nutrition tracking through AI-powered food image analysis. Simply snap a photo of your meal, and our advanced Google Gemini AI will instantly identify ingredients, uncover hidden components like cooking oils and spices, and provide comprehensive nutritional information.

### ✨ Point. Shoot. Know EVERYTHING! 
AI food scanner reveals complete nutrition + hidden ingredients in seconds.

---

## ✨ Features

### 🤖 Core AI Features
- **📸 Instant Food Recognition** - Point, shoot, and get detailed meal analysis in seconds
- **🔍 Hidden Ingredient Detection** - Discovers non-visible ingredients like oils, spices, and marinades
- **📊 Smart Nutrition Calculation** - Accurate macro and micronutrient breakdown
- **✏️ Editable Results** - Modify ingredients and recalculate nutrition instantly

### 📱 App Features
- **🌙 Beautiful Dark UI** - Elegant interface optimized for all lighting conditions
- **📈 Comprehensive Dashboard** - Track calories, water, exercise, and weight in one place
- **📊 Weekly Insights** - Beautiful charts showing your progress and trends
- **🔥 Streak Tracking** - Stay motivated with consecutive day tracking
- **🎯 Personalized Goals** - Set and monitor customized nutrition targets
- **🔐 Secure Authentication** - JWT-based auth with encrypted data storage

---

## 📱 Screenshots

<div align="center">
  <table>
    <tr>
      <td><img src="https://github.com/yourusername/nutrisnap/blob/main/screenshots/dashboard.png" width="250" alt="Dashboard"/></td>
      <td><img src="https://github.com/yourusername/nutrisnap/blob/main/screenshots/analysis.png" width="250" alt="AI Analysis"/></td>
      <td><img src="https://github.com/yourusername/nutrisnap/blob/main/screenshots/meal-detail.png" width="250" alt="Meal Detail"/></td>
    </tr>
    <tr>
      <td align="center"><b>Dashboard</b></td>
      <td align="center"><b>AI Analysis</b></td>
      <td align="center"><b>Meal Details</b></td>
    </tr>
    <tr>
      <td><img src="https://github.com/yourusername/nutrisnap/blob/main/screenshots/profile.png" width="250" alt="Profile"/></td>
      <td><img src="https://github.com/yourusername/nutrisnap/blob/main/screenshots/history.png" width="250" alt="History"/></td>
      <td><img src="https://github.com/yourusername/nutrisnap/blob/main/screenshots/tracking.png" width="250" alt="Tracking"/></td>
    </tr>
    <tr>
      <td align="center"><b>Profile Setup</b></td>
      <td align="center"><b>Meal History</b></td>
      <td align="center"><b>Health Tracking</b></td>
    </tr>
  </table>
</div>

---

## 🚀 Quick Start

### Prerequisites

- **macOS** with Xcode 15+
- **iOS 17+** Device/Simulator
- **Python 3.9+**
- **MongoDB Atlas** account (free)
- **Google AI Studio** account (free)

### 🎯 3-Step Setup

```bash
# 1. Clone the repository
git clone https://github.com/yourusername/nutrisnap.git
cd nutrisnap

# 2. Set up the backend
cd backend
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
cp .env.sample .env
# Edit .env with your API keys

# 3. Run the backend
python app.py
```

**That's it!** Open `NutriSnap.xcodeproj` in Xcode and run the app! 🎉

---

## 🛠 Tech Stack

<div align="center">
  <table>
    <tr>
      <td align="center" width="50%">
        <h3>📱 iOS Frontend</h3>
        <img src="https://img.shields.io/badge/SwiftUI-FA7343?style=for-the-badge&logo=swift&logoColor=white" alt="SwiftUI"/>
        <img src="https://img.shields.io/badge/Combine-FA7343?style=for-the-badge&logo=swift&logoColor=white" alt="Combine"/>
        <br><br>
        <ul align="left">
          <li><b>SwiftUI</b> - Modern declarative UI</li>
          <li><b>Combine</b> - Reactive state management</li>
          <li><b>Charts</b> - Native iOS charts</li>
          <li><b>PhotosUI</b> - Camera integration</li>
          <li><b>URLSession</b> - Networking with JWT</li>
        </ul>
      </td>
      <td align="center" width="50%">
        <h3>⚙️ Python Backend</h3>
        <img src="https://img.shields.io/badge/Flask-000000?style=for-the-badge&logo=flask&logoColor=white" alt="Flask"/>
        <img src="https://img.shields.io/badge/MongoDB-47A248?style=for-the-badge&logo=mongodb&logoColor=white" alt="MongoDB"/>
        <br><br>
        <ul align="left">
          <li><b>Flask</b> - REST API framework</li>
          <li><b>Google Gemini AI</b> - Vision AI model</li>
          <li><b>MongoDB</b> - NoSQL database</li>
          <li><b>JWT</b> - Secure authentication</li>
          <li><b>Gunicorn</b> - Production server</li>
        </ul>
      </td>
    </tr>
  </table>
</div>

---

## 📲 Installation

### 🔧 Backend Setup

1. **Create Python Environment**
   ```bash
   cd backend
   python3 -m venv venv
   source venv/bin/activate  # macOS/Linux
   # OR
   venv\Scripts\activate     # Windows
   ```

2. **Install Dependencies**
   ```bash
   pip install -r requirements.txt
   ```

3. **Configure Environment**
   ```bash
   cp .env.sample .env
   ```
   
   Edit `.env` with your credentials:
   ```env
   GEMINI_API_KEY=your_google_ai_api_key
   MONGO_URI=mongodb+srv://username:password@cluster.mongodb.net/
   MONGO_DB=nutrisnap
   JWT_SECRET_KEY=your-secret-key-change-this
   PORT=5000
   ```

4. **Get API Keys**
   - **Google Gemini**: Visit [Google AI Studio](https://makersuite.google.com/app/apikey)
   - **MongoDB**: Create free cluster at [MongoDB Atlas](https://www.mongodb.com/cloud/atlas)

5. **Start Backend**
   ```bash
   python app.py
   ```

### 📱 iOS App Setup

1. **Open in Xcode**
   ```bash
   cd ios
   open NutriSnap.xcodeproj
   ```

2. **Configure Backend URL**
   
   Edit `NetworkManager.swift`:
   ```swift
   private let baseURL = "http://localhost:5000"  // For local dev
   // OR
   private let baseURL = "https://your-app.onrender.com"  // For production
   ```

3. **Run the App**
   - Select target device/simulator
   - Press `Cmd + R` or click Run
   - For physical device: Enable Developer Mode

---

## 🌐 Deployment

### Deploy to Render (Free Hosting)

1. **Push to GitHub**
   ```bash
   git add .
   git commit -m "Ready for deployment"
   git push origin main
   ```

2. **Create Render Web Service**
   - Go to [Render Dashboard](https://dashboard.render.com)
   - Click "New +" → "Web Service"
   - Connect your GitHub repo
   - Configure:
     - **Name**: `nutrisnap-backend`
     - **Build Command**: `pip install -r requirements.txt`
     - **Start Command**: `gunicorn app:app`

3. **Add Environment Variables**
   ```
   GEMINI_API_KEY=your_key
   MONGO_URI=your_mongodb_uri
   MONGO_DB=nutrisnap
   JWT_SECRET_KEY=your_secret
   ENVIRONMENT=production
   ```

4. **Update iOS App**
   ```swift
   private let baseURL = "https://nutrisnap-backend.onrender.com"
   ```

---

## 🎮 How to Use

1. **📸 Capture** - Take a photo of your meal
2. **🤖 Analyze** - AI identifies all ingredients instantly
3. **📊 Review** - Check nutrition breakdown and hidden ingredients
4. **💾 Save** - Add to your food diary with one tap
5. **📈 Track** - Monitor your progress with beautiful charts

---

## 🔐 Security & Privacy

- **🔒 JWT Authentication** - Secure token-based auth
- **🛡️ Encrypted Storage** - All data encrypted at rest
- **🚫 No Data Selling** - Your data is never shared
- **📱 On-Device Processing** - Image compression before upload
- **🗑️ Data Deletion** - Delete your account anytime

---

## 🤝 Contributing

We love contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

```bash
# Fork the repo
# Create your feature branch
git checkout -b feature/AmazingFeature

# Commit your changes
git commit -m 'Add some AmazingFeature'

# Push to the branch
git push origin feature/AmazingFeature

# Open a Pull Request
```

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 👥 Team

- Utsav Doshi  
- Junyao Chen  
- Yifan Zhang  
- Zhengyuan Zhou  


---

## 🌟 Acknowledgments

- **Google Gemini AI** - Advanced vision model for food recognition
- **MongoDB Atlas** - Reliable cloud database platform
- **Render** - Simple and powerful hosting
- **SwiftUI Community** - For inspiration and support

---

<div align="center">
  <p>
    <b>NutriCam</b> - Making nutrition tracking effortless with AI 🚀
  </p>
  
  <p>
    If you find this helpful, please ⭐ this repository!
  </p>
  
  <p>
    <a href="https://apps.apple.com/app/nutrisnap">
      <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on App Store" height="60">
    </a>
  </p>
</div>


## 📜 Privacy Policy Reference ##

Reference link: https://www.termsfeed.com/live/d4b4e1ed-8150-4ccb-a430-340180b7bc9d

---

