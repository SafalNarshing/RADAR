<div align="center">

<img src="frontend/khalto/assets/Radarlogo.png" alt="RADAR logo" width="220"/>

# RADAR
### Road Assessment and Damage Accountability Reporter

**An AI-powered mobile app that detects road damage in real time, maps hazardous zones, and closes the loop between citizens and the government agencies responsible for fixing them.**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.12-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![ONNX Runtime](https://img.shields.io/badge/ONNX%20Runtime-on--device%20AI-005CED?logo=onnx&logoColor=white)](https://onnxruntime.ai)
[![Node.js](https://img.shields.io/badge/Node.js-Express%205-339933?logo=node.js&logoColor=white)](https://nodejs.org)
[![Supabase](https://img.shields.io/badge/Supabase-auth%2C%20db%20%26%20storage-3FCF8E?logo=supabase&logoColor=white)](https://supabase.com)
[![Status](https://img.shields.io/badge/Status-Hackathon%20Prototype-orange)](#-whats-not-yet-built)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

<br/>

> Built in **48 hours** at **OrchidHackX 2026**, Orchid International College, Kathmandu — since extended with a full citizen/government dual-role experience.

</div>

---

## Table of Contents

- [Problem Statement](#problem-statement)
- [Solution](#solution)
- [Features](#-features)
- [How Detection Works](#-how-detection-works)
- [Tech Stack](#-tech-stack)
- [Project Structure](#-project-structure)
- [Getting Started](#-getting-started)
- [What's Not (Yet) Built](#-whats-not-yet-built)
- [License](#-license)

---

## Problem Statement

Seven people die on Nepal's roads every day — road accidents kill roughly five times more Nepalis than all natural disasters combined. Around 60% of the national road network is in poor or fair condition, and poor road quality is a major contributor to motorcycle accidents, which dominate Nepal's traffic.

RADAR targets four gaps behind that number:

- **No data** — road damage isn't systematically mapped anywhere.
- **No awareness** — drivers get no warning before hitting a pothole or damaged stretch.
- **No accountability** — authorities have no public, verifiable record of what's broken and what's been fixed.
- **No adoption** — reporting apps and portals already exist, but nearly all of them rely on someone manually stopping, taking a photo, filling a form, and picking a category. That friction means they see near-zero real-world usage, so the data they were built to collect never actually materializes.

---

## Solution

RADAR is a single Flutter app with two roles gated behind one login: **citizens** report and drive with live hazard alerts, and **government/police** users triage those reports, dispatch fixes, and close the loop with photo proof and CCTV context — all against one shared Supabase backend.

The key difference from prior tools is **removing the manual step entirely**. Detection runs continuously and automatically from a mounted dashcam — in a citizen's car during normal driving, or in government/police vehicles already patrolling the roads — so damage gets logged passively as a byproduct of driving, with no one having to stop, photograph, or file anything. Fleets of government vehicles can effectively become a self-reporting road-survey network for free.

---

## ✨ Features

### Citizen

| Feature | Description |
|---|---|
| 📸 **Damage reporting** | Snap a photo of road damage; on-device AI detects and classifies it, then attaches GPS location automatically |
| 🚗 **Driving mode / dashcam** | Live camera feed detects road hazards ahead in real time, with voice (TTS) and visual alerts before you reach them |
| 🗺️ **Hazard map** | City-wide map of reported damage plus live CCTV camera markers, color-coded by status |
| 📊 **Report status tracking** | Follow a submitted report from `reported` → `verified` → `in_progress` → `fixed`, with before/after photos once resolved |
| 💰 **Tax-rebate rewards** | Earn rewards for verified, high-quality reports that government reviewers approve |
| 💬 **Comments** | Discuss and add context on individual reports |

### Government / Police

| Feature | Description |
|---|---|
| 🏛️ **Review dashboard** | Stats overview and a feed of incoming citizen reports awaiting triage |
| ✅ **Feed moderation** | Approve, reject, or escalate reports; update status with the `requireGovernment`-guarded API |
| 📷 **CCTV-linked map** | View reports spatially alongside live CCTV feeds for verification |
| 🖼️ **Mark as fixed** | Attach an after-photo to close out a report, generating the citizen-facing before/after comparison |
| 🎁 **Rewards management** | Review and approve citizen tax-rebate reward claims |

---

## 🔍 How Detection Works

Road damage detection runs **on-device** via ONNX Runtime — no round trip to a server is needed to spot a pothole:

```
Camera frame
     │
     ▼
[ONNX Runtime — object detection model]
     │
     ▼
[Bounding boxes + damage class + confidence]
     │
     ├──► Report flow   → attach photo + GPS, submit to Supabase
     └──► Driving mode  → overlay bounding box, trigger TTS + visual alert
```

The same detection service (`onnx_detection_service.dart`) backs both the one-shot **report** flow and the continuous **driving mode** flow, with separate native/web implementations behind a shared interface so the model runs on mobile and in-browser alike.

Verified reports and status changes are persisted through a Node/Express API backed by Supabase (Postgres + Auth + Storage), with government-only actions enforced server-side by validating the caller's Supabase access token and `government` profile role — not just by hiding the button in the UI.

---

## 🛠 Tech Stack

| Layer | Technology |
|---|---|
| Mobile app | Flutter, Dart, Provider (state management) |
| On-device AI | ONNX Runtime, custom road-damage detection model |
| Maps & location | `flutter_map` (OpenStreetMap), `geolocator`, `geocoding` |
| Camera & media | `camera`, `image_picker`, `image`, `video_player` |
| Voice alerts | `flutter_tts` |
| Backend API | Node.js, Express 5 |
| Data, auth & storage | Supabase (Postgres, Auth, Storage) |

---

## 📁 Project Structure

```
Khalto/
├── backend/                        # Express API
│   ├── index.js                    # App entry, mounts /api/potholes
│   └── routes/
│       └── potholes.js             # CRUD + government-only status transitions
│
└── frontend/khalto/                # Flutter app
    ├── lib/
    │   ├── main.dart
    │   ├── config.dart              # Supabase config
    │   ├── models/                  # Pothole, detection, CCTV camera, reward, comment
    │   ├── providers/                # Gov dashboard, gov feed, rewards state
    │   ├── services/                 # Supabase, ONNX detection, damage detection, location
    │   ├── screens/
    │   │   ├── auth/                 # Login / signup
    │   │   ├── role_gate.dart        # Routes citizen vs. government users
    │   │   ├── home_shell.dart        # Citizen tab shell
    │   │   ├── report/                # Damage scan camera, edit location, submit report
    │   │   ├── driving/               # Live dashcam driving mode with hazard alerts
    │   │   ├── dashcam/
    │   │   ├── map/                   # Citizen hazard + CCTV map
    │   │   ├── feed/                  # Citizen report feed
    │   │   ├── status/                # Report status tracking
    │   │   └── gov/                   # Government dashboard, feed, map, rewards
    │   ├── widgets/                    # Shared UI: markers, cards, overlays, before/after view
    │   └── theme/
    └── assets/                        # Radarlogo.png, ONNX model files
```

---

## 🚀 Getting Started

### Backend

```bash
cd backend
npm install
```

Create a `.env` file:

```
PORT=3000
PROJECT_URL=your-supabase-project-url
SERVICE_ROLE_KEY=your-supabase-service-role-key
```

```bash
npm start
```

Runs at `http://localhost:3000`.

### Frontend (Flutter app)

```bash
cd frontend/khalto
flutter pub get
flutter run
```

Update `lib/config.dart` with your own Supabase URL and anon key before running against your own project.

---

## 🧩 What's Not (Yet) Built

- No automated CI/CD or test suite yet — this started as a hackathon build.
- Reward payout is tracked in-app only; there's no real integration with a tax authority system.
- CCTV feeds are linked by camera marker/location, not pulled from a live video ingestion pipeline.

---

## 📄 License

This project is licensed under the **MIT License** — see [LICENSE](LICENSE) for details.

---

<div align="center">

If this project interests you, consider giving it a ⭐

</div>
