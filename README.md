# 🍽️ MakanManoi
### By Team Imperium

MakanManoi is an AI-powered restaurant intelligence platform built with Flutter and Google technologies.  
It transforms unstructured TikTok food reviews into structured, credibility-based insights to help users make faster, smarter, and more responsible dining decisions.

---

## 📌 Overview

In today’s digital food economy, students and young consumers rely heavily on viral TikTok reviews to decide where to eat. However, these reviews are often exaggerated, sponsored, or emotionally biased.

MakanManoi solves this by:

- 🎥 Transcribing TikTok video reviews into text
- 🧠 Performing AI-powered sentiment analysis
- 📝 Generating concise review summaries
- 🍜 Extracting frequently mentioned dishes
- 📊 Producing a “Hype vs Reality” Trust Score
- 📍 Providing direct navigation via Google Maps

Our system converts scattered social media opinions into clear, structured, decision-ready insights.

---

## 🌍 SDG Alignment

MakanManoi aligns with:

**United Nations Sustainable Development Goal 12 – Responsible Consumption and Production**  
**Target 12.8 – Ensure people have relevant information for informed decision-making.**

By reducing information asymmetry in social-media-driven food discovery, we promote transparency, trust, and responsible consumer behavior.

---

## 🚀 Key Features

- TikTok review submission
- AI-powered sentiment analysis (Gemini API)
- Hype vs Reality Trust Score
- Automatic dish extraction
- AI-generated summaries (Pros / Cons / Highlights)
- Google Maps route integration
- Real-time database updates via Firebase
- User engagement tracking via Firebase Analytics

---

## 🏗️ Architecture Overview

MakanManoi consists of four core components:

### 1️⃣ Frontend (Flutter)
- Cross-platform mobile application
- Displays restaurant insights and analytics
- Handles submissions and user interactions

### 2️⃣ Backend (Firebase & Firestore)
- Authentication
- Real-time database storage
- Video & restaurant data aggregation

### 3️⃣ AI Processing Layer
- OpenAI Whisper / Google Speech-to-Text → Transcription
- Gemini API → Sentiment analysis, summarization, dish extraction, trust scoring
- Google Cloud Vision API → Image analysis

### 4️⃣ Location Intelligence
- Google Maps API → Restaurant visualization
- Route navigation integration

This modular design allows independent scaling of UI, backend, and AI processing.

---

## 🤖 Google Technologies Used

| Technology | Purpose |
|------------|----------|
| Gemini API (Google AI Studio) | Sentiment analysis, summarization, dish extraction, trust scoring |
| Firebase | Authentication & real-time database |
| Firebase Analytics | User engagement tracking |
| Google Cloud Platform | Backend hosting & scalability |
| Google Maps API | Location search & navigation |


**Non-Google AI:**  
- OpenAI Whisper (for enhanced speech transcription testing)

---

## 📊 Impact Metrics

We measure success using:

- ✅ 70%+ user-reported increase in decision confidence  
- ⏱ 30% reduction in decision-making time  
- 📈 60%+ willingness to use regularly  

These metrics validate improved transparency, efficiency, and trust in dining decisions.

---

## 🧪 Getting Started

### Prerequisites

- Flutter SDK
- Firebase Project
- Google Cloud Project
- API keys for:
  - Gemini API
  - Google Maps API
  - Google Cloud Vision
  - Google Cloud Speech-to-Text

---

### Installation

Clone the repository:

```bash
git clone https://github.com/your-username/makanmanoi.git
cd makanmanoi
flutter pub get
