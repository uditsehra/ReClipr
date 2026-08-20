# 📋 ReClipr — macOS Clipboard Manager

ReClipr is a **lightweight macOS menu bar clipboard manager** built using **SwiftUI and AppKit**.  
It helps you keep track of copied text, images, and files, while providing **duplicate handling**, **source tracking**, and **privacy-aware filtering**.

This project is a **hands-on learning exercise** to understand macOS application development, system APIs, and clipboard management.

---

## ✨ Features

- 📌 **Menu Bar Clipboard Access**
  - Runs quietly in the macOS menu bar
  - One-click access to clipboard history

- 📝 **Multi-Type Clipboard Support**
  - Text
  - Images
  - Files & URLs

- 🔁 **Duplicate Handling Policies**
  - No duplicates
  - Time-based duplicates
  - Always allow duplicates

- 🕵️ **Source App Tracking**
  - Stores the application from which content was copied
  - Useful for identifying where a clip originated

- 🔍 **Search & Filter**
  - Search clipboard items by content
  - Search by source application name

- 🚫 **Ignore Sensitive Applications**
  - Exclude clipboard entries from selected apps
  - Helps prevent storing sensitive data (e.g. password managers)

- 💾 **Persistence**
  - Clipboard history is saved and restored across app launches

- ⚙️ **Preferences Window**
  - Configure duplicate behavior
  - Manage ignored apps
  - Keyboard shortcut

---

## 🧠 How It Works

- Uses `NSPasteboard` to monitor clipboard changes
- Polls clipboard safely using a timer-based approach
- Stores clipboard items using a structured `ClipItem` model
- Saves data locally using a lightweight persistence layer
- SwiftUI is used for UI, while AppKit bridges system-level APIs

---

## 🛠 Tech Stack

- **Language:** Swift  
- **UI:** SwiftUI  
- **System APIs:** AppKit  
- **Platform:** macOS
-  **Architecture:** MV-style separation (Monitor, Store, Model, UI)

---

## 📂 Project Structure

-  ReClipr/
-  |--App/
-  |--ReCliprApp.swift
-  |--Clipboard/
-  │ |-- ClipboardMonitor.swift
-  │   |-- ClipboardStore.swift
-  |--Model/
-  │   |---ClipContent.swift
-  │   |---ClipItem.swift
-  |--Persistence/
-  │   |---Persistence.swift
-  |--UI/
-  │  |-- Menu/
-  │  |-- Preferences/
-  |--LoginHelper/




---

## 🚀 Getting Started

1. Clone the repository
   ```bash
   git clone https://github.com/your-username/ReClipr.git

2. open ReClipr.xcodeproj
