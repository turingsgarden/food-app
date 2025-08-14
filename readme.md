# 🍎 NutriSnap - AI-Powered Nutrition Tracker

NutriSnap is a cutting-edge iOS application that revolutionizes nutrition tracking through AI-powered food image analysis. Simply snap a photo of your meal, and our advanced Google Gemini AI will instantly identify ingredients, uncover hidden components like cooking oils and spices, and provide comprehensive nutritional information.

### 🎯 Key Highlights

- **Instant Food Recognition**: Point, shoot, and get detailed meal analysis in seconds
- **Hidden Ingredient Detection**: Discovers non-visible ingredients like oils, spices, and marinades
- **Comprehensive Tracking**: Monitor calories, water intake, exercise, and weight all in one place
- **Beautiful Dark UI**: Elegant interface optimized for all lighting conditions
- **Smart Insights**: Personalized recommendations based on your goals and habits

## ✨ Main Features

### 🔍 AI-Powered Food Analysis
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
- **Secure Authentication**: Email/password with session management
- **Data Privacy**: Your data is encrypted and secure

## 🛠️ Technology Stack

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
- **Pillow** - Advanced image processing
- **Flask-CORS** - Cross-origin resource sharing

## 🚀 Setup Guide

### Prerequisites

- **macOS** with Xcode 15 or later
- **iOS Device/Simulator** running iOS 17+
- **Python 3.9+** installed
- **MongoDB Atlas** account (free tier)
- **Google AI Studio** account (free)
- **Render** account (optional, for deployment)

### 🔧 Step 1: Clone Repository

```bash
git clone https://github.com/yourusername/FOOD-APP-SWIFT.git
cd FOOD-APP-SWIFT
```

### 🐍 Step 2: Backend Setup

#### 2.1 Create Python Virtual Environment

```bash
# Create virtual environment
python3 -m venv venv

# Activate it
source venv/bin/activate  # macOS/Linux
# OR
venv\Scripts\activate     # Windows
```

#### 2.2 Install Dependencies

```bash
pip install -r requirements.txt
```

#### 2.3 Configure Environment Variables

Create `.env` file from template:
```bash
cp .env_sample .env
```

Edit `.env` with your credentials:
```env
GEMINI_API_KEY=your_gemini_api_key_here
MONGO_URI=mongodb+srv://username:password@cluster.mongodb.net/?retryWrites=true&w=majority
MONGO_DB=food-app-swift
PORT=5000
```

#### 2.4 Get Google Gemini API Key

1. Visit [Google AI Studio](https://makersuite.google.com/app/apikey)
2. Sign in with Google account
3. Click "Create API Key"
4. Select "Create API key in new project"
5. Copy the generated key to `.env`

#### 2.5 Start Backend Server

```bash
python app.py
```

You should see:
```
🚀 Starting Food Analyzer Backend on port 5000
✅ Based on proven working web app backend
🤖 Using Gemini AI with tested prompts
📱 Compatible with Swift frontend
 * Running on http://0.0.0.0:5000
```

### 🗄️ Step 3: MongoDB Atlas Setup

#### 3.1 Create Free Cluster

1. Go to [MongoDB Atlas](https://www.mongodb.com/cloud/atlas/register)
2. Sign up or log in
3. Click "Build a Database"
4. Choose **FREE** Shared Cluster
5. Select cloud provider (AWS recommended)
6. Choose nearest region
7. Name cluster: `NutriSnapCluster`

#### 3.2 Configure Database Access

1. Navigate to **Database Access** (left sidebar)
2. Click "Add New Database User"
3. Authentication Method: Password
4. Username: `nutrisnap-user`
5. Password: Generate secure password
6. Database User Privileges: "Read and write to any database"
7. Click "Add User"

#### 3.3 Configure Network Access

1. Navigate to **Network Access** (left sidebar)
2. Click "Add IP Address"
3. For development: Click "Add Current IP Address"
4. For production: Add `0.0.0.0/0` (allows all IPs)
5. Click "Confirm"

#### 3.4 Get Connection String

1. Go to **Database** → **Connect** → **Drivers**
2. Select "Python" and version "3.12 or later"
3. Copy connection string:
   ```
   mongodb+srv://nutrisnap-user:<password>@nutrisnap.xxxxx.mongodb.net/?retryWrites=true&w=majority
   ```
4. Replace `<password>` with your database password
5. Add to `.env` as `MONGO_URI`

#### 3.5 Database Structure

MongoDB collections (auto-created):
- `users` - User accounts and authentication
- `profiles` - User profiles and preferences
- `meals` - Saved meal entries with images
- `water` - Water intake logs
- `exercise` - Exercise activity logs
- `weight` - Weight tracking entries

### 📱 Step 4: iOS App Setup

#### 4.1 Open in Xcode

```bash
cd food-app-swift
open food-app-swift.xcodeproj
```

#### 4.2 Configure Backend URL

Edit `NetworkManager.swift`:
```swift
// For local development:
private let baseURL = "http://localhost:5000"

// For production (after Render deployment):
private let baseURL = "https://food-analyzer.onrender.com"
```

#### 4.3 Update Bundle Identifier

1. Select project in Xcode navigator
2. Select target "food-app-swift"
3. Change Bundle Identifier to: `com.yourname.nutrisnap`
4. Update Team (if deploying to device)

#### 4.4 Run the App

1. Select target device (iPhone 15 Pro recommended)
2. Press `Cmd + R` or click Run button
3. For physical device:
   - Enable Developer Mode on iPhone
   - Trust developer certificate

### 🌐 Step 5: Deploy to Render

#### 5.1 Prepare Repository

```bash
# Ensure all changes are committed
git add .
git commit -m "Ready for deployment"
git push origin main
```

#### 5.2 Create Render Web Service

1. Go to [Render Dashboard](https://dashboard.render.com)
2. Click **"New +"** → **"Web Service"**
3. Connect GitHub/GitLab account
4. Select your repository
5. Configure service:

   **Basic Settings:**
   - Name: `food-analyzer`
   - Region: Choose nearest to you
   - Branch: `main`
   - Root Directory: *(leave blank)*
   - Environment: `Python 3`
   - Build Command: `pip install -r requirements.txt`
   - Start Command: `gunicorn app:app --workers 2 --threads 4 --timeout 120`

   **Instance Type:**
   - Select "Free" ($0/month)

#### 5.3 Add Environment Variables

In Render dashboard, add these environment variables:

| Key | Value |
|-----|-------|
| `GEMINI_API_KEY` | Your Google AI API key |
| `MONGO_URI` | Your MongoDB connection string |
| `MONGO_DB` | `food-app-swift` |
| `PYTHON_VERSION` | `3.9.19` |

#### 5.4 Deploy

1. Click "Create Web Service"
2. Wait for build and deployment (5-10 minutes)
3. Your service URL will be: `https://food-analyzer.onrender.com`
4. Test with: `https://food-analyzer.onrender.com/health`

#### 5.5 Update iOS App

Update `NetworkManager.swift` with your Render URL:
```swift
private let baseURL = "https://food-analyzer.onrender.com"
```

## 📡 API Endpoints

### Health Check
```
GET /health
GET /ping
GET /
```

### Authentication
```
POST /register         - Create new account
POST /login           - User authentication
```

### Profile Management
```
GET  /get-profile     - Fetch user profile
POST /save-profile    - Create/update profile
```

### Meal Operations
```
POST   /analyze              - Analyze food image
POST   /save-meal           - Save analyzed meal
GET    /user-meals          - Get meal history
PUT    /update-meal         - Update meal details
DELETE /delete-meal         - Delete a meal
POST   /recalculate-nutrition - Recalculate nutrition
```

### Health Tracking
```
POST /add-water       - Log water intake
GET  /user-water      - Get water history
POST /add-exercise    - Log exercise
GET  /user-exercise   - Get exercise history
POST /add-weight      - Log weight
GET  /user-weight     - Get weight history
```

### Analytics
```
GET /dashboard-stats  - Dashboard statistics
GET /user-insights    - Personalized insights
```

## 🔑 Environment Variables

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `GEMINI_API_KEY` | Google AI API key | `AIzaSy...` |
| `MONGO_URI` | MongoDB connection string | `mongodb+srv://...` |
| `MONGO_DB` | Database name | `food-app-swift` |
| `PORT` | Server port (optional) | `5000` |

### Getting API Keys

**Google Gemini API:**
1. Visit [Google AI Studio](https://makersuite.google.com/app/apikey)
2. Create new API key
3. No credit card required
4. 60 requests/minute free tier

**MongoDB Atlas:**
1. Create free M0 cluster
2. 512MB storage included
3. Suitable for thousands of meals

## 🐛 Troubleshooting

### Backend Issues

**Problem: "ModuleNotFoundError"**
```bash
# Solution: Activate virtual environment
source venv/bin/activate
pip install -r requirements.txt
```

**Problem: "Connection timeout to MongoDB"**
- Check MongoDB Network Access allows your IP
- Verify connection string format
- Ensure password is URL-encoded if contains special characters

**Problem: "Gemini API error"**
- Verify API key is active
- Check quota limits (60/minute)
- Ensure image size < 10MB

### iOS App Issues

**Problem: "Could not connect to server"**
- Verify backend is running
- Check NetworkManager URL
- For simulator: Use `localhost`
- For device: Use machine's IP address

**Problem: "Camera not working"**
- Check Info.plist has camera permissions
- Accept permission dialog
- Restart app if needed

### Render Deployment Issues

**Problem: "Build failed on Render"**
- Check Python version matches
- Verify all dependencies in requirements.txt
- Check build logs for specific errors

**Problem: "Cold start delays"**
- Normal for free tier (spins down after 15 min)
- First request takes 30-60 seconds
- Consider upgrading for always-on service

## 🎯 Performance Optimization

### Image Processing
- Auto-resize to 800px max dimension
- JPEG compression at 85% quality
- Separate thumbnails at 100KB
- Base64 encoding for storage

### Database Performance
- Compound indexes on (user_id, saved_at)
- Connection pooling (50 connections)
- 30-second idle timeout
- Aggregation pipelines for stats

### Caching Strategy
- Profile data: 5-minute local cache
- Meal images: Stored as base64
- API responses: No server-side caching
- Session persistence in UserDefaults

## 🔒 Security Features

- **Password Security**: SHA256 hashing (upgrade to bcrypt recommended)
- **Session Management**: Secure token-based sessions
- **API Validation**: User ID required for all endpoints
- **CORS Protection**: Configured for production domain
- **MongoDB Security**: TLS/SSL encryption enforced
- **Environment Variables**: Sensitive data never in code

## 📊 Usage Limits

### Free Tier Limits
- **Render**: 750 hours/month, spins down after 15 min
- **MongoDB Atlas**: 512MB storage, 100 connections
- **Google Gemini**: 60 requests/minute, 2M tokens/month
- **Image Size**: 10MB maximum per upload

## 🚧 Known Issues & Roadmap

### Current Limitations
- Cold start delays on free hosting
- Basic password hashing (SHA256)
- No push notifications
- Limited offline support

### Planned Features
- [ ] Social sharing capabilities
- [ ] Barcode scanning
- [ ] Recipe suggestions
- [ ] Apple Health integration
- [ ] Meal planning
- [ ] Restaurant menu integration
- [ ] Voice input for logging
- [ ] Apple Watch app

## 🤝 Contributing

We welcome contributions! Please follow these steps:

1. Fork the repository
2. Create feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit changes (`git commit -m 'Add AmazingFeature'`)
4. Push to branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### Code Style
- **Swift**: Follow Swift API Design Guidelines
- **Python**: PEP 8 compliance
- **Comments**: Clear and concise
- **Testing**: Add tests for new features

## 📄 License

This project is licensed under the MIT License - see [LICENSE](LICENSE) file for details.

## 👏 Credits & Acknowledgments

### Technologies
- **Google Gemini AI** - Advanced vision model for food recognition
- **MongoDB Atlas** - Reliable cloud database platform
- **Render** - Simple and powerful hosting platform
- **SwiftUI** - Modern iOS development framework

### Resources
- Nutrify Datasets - Nutritional reference data
- iOS Development Community
- Flask Documentation
- MongoDB University

### Special Thanks
- Beta testers for valuable feedback
- Open source contributors
- Stack Overflow community

## 📞 Contact & Support

**Developer**: Utsav Doshi, Junyao Chen, Zhengyuan Zhou, Yifan Zhang

**Support Options:**
- 📧 Email: support@nutrisnap.app
- 🐛 Issues: [GitHub Issues](https://github.com/yourusername/FOOD-APP-SWIFT/issues)
- 📖 Wiki: [Documentation](https://github.com/yourusername/FOOD-APP-SWIFT/wiki)
- 💬 Discord: [Community Server](https://discord.gg/nutrisnap)

**Project Links:**
- 🌐 Website: [nutrisnap.app](https://nutrisnap.app)
- 📱 App Store: [Download NutriSnap](https://apps.apple.com/app/nutrisnap)
- 🐙 GitHub: [Source Code](https://github.com/yourusername/FOOD-APP-SWIFT)

## 📜 Privacy Policy Reference ##

Reference link: https://www.termsfeed.com/live/d4b4e1ed-8150-4ccb-a430-340180b7bc9d

---

<div align="center">
  <b>NutriSnap</b> - Making nutrition tracking effortless with AI 🚀
  <br><br>
  If you find this project helpful, please consider giving it a ⭐️
