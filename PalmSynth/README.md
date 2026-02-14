# PalmSynth (MVP)

A SwiftUI iOS MVP: camera + Vision hand tracking + gesture-mapped audio (AVAudioEngine) + simple SceneKit visuals.

## What you get
- User picks a local audio file via Files/iCloud Drive (Document Picker).
- Plays it via AVAudioEngine + EQ (bass) + optional reverb burst.
- Vision hand pose tracking:
  - **Intro gesture**: *"fingertips-only" hold* (sideways hand so mainly fingertips are visible) triggers a short **camera pan** + **audio fade-in** + **visual burst**.
  - **Intensity**: hand height controls volume + visual intensity.
  - **Bass**: finger openness controls bass gain (EQ low band).
  - **Pinch**: thumb-index pinch triggers a reverb burst.
- First-launch tutorial overlay (tap to dismiss) + help button to revisit.

## Requirements
- Xcode 15+ (iOS 17+ recommended)
- Real device (camera required)

## Setup
1) Create a new iOS App in Xcode (SwiftUI, Swift).
2) Drag the entire **PalmSynth** folder (this one) into your Xcode project navigator.
   - Ensure **"Copy items if needed"** is checked.
   - Add to your app target.
3) Add this key to your app target Info.plist:
   - **NSCameraUsageDescription** = "Camera is used to track hand gestures to control music and visuals."
4) Build & run on a real device.

## Notes / Gotchas
- Apple Music streaming/DRM tracks will not work. Use Files/iCloud local audio files (mp3, m4a, wav, aiff, etc.).
- Fingertips-only gesture is heuristic. Best results: bright lighting + plain background.

## Gestures (default)
- **Intro Hold (fingertips-only)**: hold sideways hand so only tips are confidently detected for ~0.8s.
- **Hand height**: raise/lower hand to increase/decrease intensity.
- **Open/close fingers**: increases/decreases bass.
- **Pinch**: thumb+index pinch triggers reverb burst while pinching.
