# <div align="center">
  <img src="https://github.com/yourusername/nutrisnap/blob/main/assets/nutrisnap-logo.png" alt="NutriSnap Logo" width="120" height="120">
  
  # NutriSnap - AI Food Tracker
  
  ### ✨ Point. Shoot. Know EVERYTHING!
  #### AI food scanner reveals complete nutrition + hidden ingredients in seconds.
  
  [![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg?style=flat-square)](https://swift.org)
  [![iOS](https://img.shields.io/badge/iOS-17%2B-blue.svg?style=flat-square)](https://www.apple.com/ios/)
  [![Python](https://img.shields.io/badge/Python-3.9%2B-blue.svg?style=flat-square)](https://python.org)
  [![License](https://img.shields.io/badge/License-MIT-green.svg?style=flat-square)](LICENSE)
  
  [Download on App Store](#) • [Demo Video](#) • [Documentation](#)
</div>

---

## 📱 Screenshots

<div align="center">
  <img src="https://github.com/yourusername/nutrisnap/blob/main/screenshots/onboarding.png" width="200" alt="Onboarding">
  <img src="https://github.com/yourusername/nutrisnap/blob/main/screenshots/dashboard.png" width="200" alt="Dashboard">
  <img src="https://github.com/yourusername/nutrisnap/blob/main/screenshots/camera.png" width="200" alt="Camera">
  <img src="https://github.com/yourusername/nutrisnap/blob/main/screenshots/analysis.png" width="200" alt="Analysis">
</div>

<div align="center">
  <img src="https://github.com/yourusername/nutrisnap/blob/main/screenshots/meal-detail.png" width="200" alt="Meal Detail">
  <img src="https://github.com/yourusername/nutrisnap/blob/main/screenshots/nutrition.png" width="200" alt="Nutrition">
  <img src="https://github.com/yourusername/nutrisnap/blob/main/screenshots/profile.png" width="200" alt="Profile">
  <img src="https://github.com/yourusername/nutrisnap/blob/main/screenshots/history.png" width="200" alt="History">
</div>

---

## 🌟 About NutriSnap

**Your Personal AI Nutritionist in Your Pocket!** 🚀

NutriSnap revolutionizes nutrition tracking through AI-powered food image analysis. Simply snap a photo of your meal, and our advanced Google Gemini AI will instantly identify ingredients, uncover hidden components like cooking oils and spices, and provide comprehensive nutritional information.

### 🎯 Key Highlights

- **🤖 AI Food Scanner** - Point, shoot, and boom! Instant nutrition facts
- **🔍 Hidden Ingredient Detector** - Uncovers secret calories lurking in your meals  
- **📊 Smart Nutrition Tracking** - Calories, protein, carbs & more calculated automatically
- **🌙 Beautiful Dark Mode** - Easy on the eyes, stunning visuals
- **📈 Weekly Insights** - Gorgeous charts show your progress
- **⚡ Lightning Fast** - Results in seconds, not minutes

---

## ✨ Main Features

### 🔍 AI-Powered Food Analysis
<img align="right" src="https://github.com/yourusername/nutrisnap/blob/main/assets/ai-analysis-demo.gif" width="250" alt="AI Analysis Demo">

- **Multi-Dish Recognition**: Identifies multiple dishes in a single photo
- **Ingredient Detection**: Lists all visible ingredients with quantities
- **Hidden Ingredients**: AI detects cooking methods and hidden ingredients
- **Nutrition Calculation**: Accurate macro and micronutrient breakdown
- **Editable Results**: Modify ingredients and recalculate nutrition instantly

### 📊 Comprehensive Dashboard
- **Daily Overview**: Track calories, water, exercise at a glance
- **Progress Visualization**: Beautiful charts showing weekly/monthly trends
- **Streak Tracking**: Stay motivated with consecutive day tracking
- **Goal Management**: Set and monitor personalized nutrition targets
- **Real-time Updates**: Instant sync across all your data

### 🏃‍♂️ Health Tracking Suite
- **Water Intake**: Visual progress with quick-add buttons
- **Exercise Logging**: Track duration, intensity, and calories burned
- **Weight Management**: Monitor trends with interactive charts
- **Meal History**: Searchable database of all your meals
- **Custom Meal Types**: Breakfast, Lunch, Dinner, Snacks

### 👤 User Profile & Personalization
- **Profile Setup**: Age, gender, activity level configuration
- **Calorie Goals**: Automatic calculation based on your profile
- **Dietary Preferences**: Vegetarian, Keto, Gluten-free options
- **Secure Authentication**: JWT-based session management
- **Data Privacy**: Your data is encrypted and secure

---

## 🚀 Quick Start

### Prerequisites

- **macOS** with Xcode 15 or later
- **iOS Device/Simulator** running iOS 17+
- **Python 3.9+** installed
- **MongoDB Atlas** account (free tier)
- **Google AI Studio** account (free)

### 🎮 How to Run

#### 1️⃣ Clone the Repository

```bash
git clone https://github.com/yourusername/nutrisnap.git
cd nutrisnap
```

#### 2️⃣ Backend Setup

```bash
# Navigate to backend directory (if separate)
cd backend

# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Create .env file
cp .env_sample .env

# Edit .env with your credentials
# GEMINI_API_KEY=your_key_here
# MONGO_URI=your_mongodb_uri_here
# JWT_SECRET_KEY=your_secret_key_here

# Run the backend
python app.py
```

#### 3️⃣ iOS App Setup

```bash
# Open in Xcode
cd ../food-app-swift
open food-app-swift.xcodeproj

# In NetworkManager.swift, update the baseURL:
# For local testing: http://localhost:5000
# For production: https://your-backend-url.com

# Select your target device and press Cmd+R to run
```

---

## 🛠️ Technology Stack

<div align="center">
  <img src="https://github.com/yourusername/nutrisnap/blob/main/assets/tech-stack.png" alt="Tech Stack" width="80%">
</div>

### iOS Frontend
- **SwiftUI** - Modern declarative UI framework
- **Combine** - Reactive programming for state management
- **Charts** - Native iOS charts for data visualization
- **PhotosUI** - Camera and photo library integration
- **URLSession** - Robust networking with error handling

### Python Backend
- **Flask** - Lightweight REST API framework
- **Google Gemini AI** - State-of-the-art vision AI model
- **MongoDB + PyMongo** - NoSQL database with connection pooling
- **Gunicorn** - Production-grade WSGI server
- **JWT + Bcrypt** - Secure authentication system
- **Pillow** - Advanced image processing
- **Flask-CORS** - Cross-origin resource sharing

---

## 📸 How It Works

<div align="center">
  <img src="https://github.com/yourusername/nutrisnap/blob/main/assets/how-it-works.png" alt="How It Works" width="80%">
</div>

1. **📸 Take a Photo** - Snap your meal using camera or gallery
2. **🤖 AI Analyzes** - Gemini AI identifies all ingredients
3. **📊 Get Results** - View complete nutrition breakdown
4. **💾 Save & Track** - Store in your personal food diary

---

## 🔧 API Endpoints

| Endpoint | Method | Description | Auth Required |
|----------|--------|-------------|---------------|
| `/health` | GET | Health check | ❌ |
| `/register` | POST | Create new account | ❌ |
| `/login` | POST | User authentication | ❌ |
| `/analyze` | POST | Analyze food image | ✅ |
| `/save-meal` | POST | Save analyzed meal | ✅ |
| `/user-meals` | GET | Get meal history | ✅ |
| `/recalculate-nutrition` | POST | Recalculate nutrition | ✅ |
| `/dashboard-stats` | GET | Dashboard statistics | ✅ |
| `/user-insights` | GET | Personalized insights | ✅ |

---

## 🔐 Security & Privacy

<img align="right" src="https://github.com/yourusername/nutrisnap/blob/main/assets/security-icon.png" width="150" alt="Security">

- **🔒 JWT Authentication** - Secure token-based sessions
- **🔑 Bcrypt Password Hashing** - Industry-standard encryption
- **🛡️ HTTPS Enforcement** - All data transmitted securely
- **📱 Session Management** - Auto-logout on app termination
- **🗄️ MongoDB Security** - TLS/SSL encryption enforced
- **🚫 No Data Selling** - Your data is never sold to third parties

---

## 📱 App Store

<div align="center">
  <a href="#"><img src="https://github.com/yourusername/nutrisnap/blob/main/assets/app-store-badge.png" alt="Download on App Store" width="200"></a>
</div>

### App Store Description

> **NutriSnap - AI Food Tracker**
> 
> Your Personal AI Nutritionist in Your Pocket! 🚀
> 
> Snap. Analyze. Transform your health! 🎯
> 
> NutriSnap uses cutting-edge AI to instantly reveal EVERYTHING about your food - even the hidden stuff! Our AI detective spots invisible ingredients like cooking oils, spices, and marinades that other apps miss. 🕵️‍♂️

**Keywords**: ai, food, tracker, nutrition, calorie, scanner, camera, diet, macro, health, weight, water, meal, photo, analyze

---

## 🤝 Contributing

We welcome contributions! Please follow these steps:

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### Code Style
- **Swift**: Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- **Python**: PEP 8 compliance
- **Comments**: Clear and concise
- **Testing**: Add tests for new features

---

## 👥 Team

<div align="center">
  <table>
    <tr>
      <td align="center">
        <img src="https://github.com/utsavdoshi.png" width="100px;" alt="Utsav Doshi"/><br />
        <sub><b>Utsav Doshi</b></sub><br />
        <a href="https://github.com/utsavdoshi">Lead Developer</a>
      </td>
      <td align="center">
        <img src="https://github.com/junyaochen.png" width="100px;" alt="Junyao Chen"/><br />
        <sub><b>Junyao Chen</b></sub><br />
        <a href="https://github.com/junyaochen">iOS Developer</a>
      </td>
      <td align="center">
        <img src="https://github.com/zhengyuanzhou.png" width="100px;" alt="Zhengyuan Zhou"/><br />
        <sub><b>Zhengyuan Zhou</b></sub><br />
        <a href="https://github.com/zhengyuanzhou">Backend Developer</a>
      </td>
      <td align="center">
        <img src="https://github.com/yifanzhang.png" width="100px;" alt="Yifan Zhang"/><br />
        <sub><b>Yifan Zhang</b></sub><br />
        <a href="https://github.com/yifanzhang">AI/ML Engineer</a>
      </td>
    </tr>
  </table>
</div>

---

## 📞 Support & Contact

<div align="center">
  
  **Need Help?** We're here for you!
  
  📧 **Email**: [support@nutrisnap.app](mailto:nutrisnap@gmail.com)  
  🐛 **Issues**: [GitHub Issues](https://github.com/yourusername/nutrisnap/issues)  
  📖 **Wiki**: [Documentation](https://github.com/yourusername/nutrisnap/wiki)  
  💬 **Discord**: [Community Server](https://discord.gg/nutrisnap)
  
</div>

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

<div align="center">
  <img src="https://github.com/yourusername/nutrisnap/blob/main/assets/nutrisnap-banner.png" alt="NutriSnap Banner" width="100%">
  
  <h3>Made with ❤️ by the NutriSnap Team</h3>
  
  **NutriSnap** - Making nutrition tracking effortless with AI 🚀
  
  If you find this project helpful, please consider giving it a ⭐️
  
  <br>
  
  [![GitHub stars](https://img.shields.io/github/stars/yourusername/nutrisnap?style=social)](https://github.com/yourusername/nutrisnap/stargazers)
  [![GitHub forks](https://img.shields.io/github/forks/yourusername/nutrisnap?style=social)](https://github.com/yourusername/nutrisnap/network/members)
  [![Twitter Follow](https://img.shields.io/twitter/follow/nutrisnap?style=social)](https://twitter.com/nutrisnap)
</div>