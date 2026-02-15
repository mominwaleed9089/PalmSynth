This is a demo project for a fun idea i had, playing with music inspired by the BMW air control knob thing. Right now it only controls a couple of settings, yes it's a bit buggy but gets the job dojne nicely.
It is only a MacOs running Demo.

*PalmSynth - Real-Time Hand Gesture Audio*

Controller
Overview
PalmSynth is a macOS application built using SwiftUI, Vision, and AVFoundation. It uses real-time
hand tracking to control audio playback using natural gestures.
*Core Features*

• Dual-hand tracking using Vision framework
• Left-hand pinch controls volume
• Right-hand pinch controls bass (low-shelf EQ)
• Real-time skeletal hand overlay
<img width="891" height="434" alt="Screenshot 2026-02-15 at 6 06 45 PM" src="https://github.com/user-attachments/assets/0f93a809-788c-4794-8658-9db293b825a7" />


• Local MP3 file selection
• Low-latency AVAudioEngine playback
• Gesture smoothing and hysteresis for stability

*How It Works*

Hand tracking is performed using VNDetectHumanHandPoseRequest. Each detected hand
computes pinch distance and joint positions. Pinch distance is normalized relative to the view size
and mapped to audio parameters using exponential smoothing and nonlinear curves for natural
responsiveness.

*Audio Engine Architecture*

Audio playback is handled using AVAudioEngine. The signal chain is: AVAudioPlayerNode ->
AVAudioUnitEQ -> MainMixerNode -> Output. Volume is controlled via the main mixer. Bass is
controlled using a low-shelf EQ band centered around 120Hz.
Controls
• Choose Audio: Select local MP3 file
• Left Hand Pinch: Adjust volume
• Right Hand Pinch: Adjust bass
• Release pinch: Hold current value

*Known Limitations*

• Hand ID may swap if hands cross
• Low lighting reduces tracking confidence
• Extreme angles may reduce landmark accuracy

Made by me the author Momin
