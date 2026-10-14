# Photo Picker

An iPhone app that finds bursts of similar photos (the five shots you took of the same view) and picks the best one from each set, so you don't have to.

Everything runs on the phone with Apple's Vision framework. No photos are uploaded anywhere.

## How it works

1. **Pick a date range.** For example, the dates of a trip.
2. **Group similar shots.** Each photo gets a Vision *feature print*, a fingerprint of what's in the image. Photos taken within a few minutes of each other whose fingerprints are close end up in the same group. Groups stay open while you shoot, so interleaved shots (A, B, A, B) still sort correctly.
3. **Rank each group.** Scores are relative to the other photos in the same group:
   | Signal | How | Weight |
   |---|---|---|
   | Sharpness | Variance of the Laplacian (catches motion blur and missed focus), measured on the subject (faces, the pet, or whatever Vision thinks draws the eye) so busy backgrounds don't win | 35% |
   | Faces | Vision face capture quality (eyes open, in focus, facing camera), weighted toward the worst face in the shot | 30% (only when people are in the shot) |
   | Pets | Cat/dog fully in frame (cut-off heads lose points) and both eyes visible | 30% (only when a cat or dog is in the shot) |
   | Composition | Apple's aesthetics score (iOS 18+) | 20% |
   | Exposure | Penalises very dark or bright frames and blown highlights | 15% |
   | Favorite | Photos you already ♥'d get a bonus | +15% |
4. **Decide what to keep.** The ★ pick in each group is kept. If the runner-up scores within 5% of it, both are kept and the group is marked *Too close to call*. Exact ties go to the later shot. Optionally, when a group has both portrait and landscape shots, the best of each is kept.
5. **Review.** Tap a thumbnail to keep or discard it, or tap **Compare** to swipe through full-screen with a score breakdown.
6. **Delete extras.** The discarded photos move to **Recently Deleted**, where you can recover them for 30 days.

## Running it on your iPhone

You need a Mac with **Xcode 16 or newer** and an iPhone on **iOS 17+**. iOS 18+ also turns on the composition score. A free Apple ID is enough; you don't need a paid developer account.

1. Clone this repo and open `PhotoPicker.xcodeproj`.
2. Select the **PhotoPicker** target, open **Signing & Capabilities**, choose your Apple ID as the *Team*, and change the *Bundle Identifier* to something unique (e.g. `com.yourname.photopicker`).
3. Plug in your iPhone, select it as the run destination, and press **⌘R**.
4. The first time, on the iPhone go to **Settings › General › VPN & Device Management** and trust your developer certificate. You may also need to turn on **Developer Mode** (Settings › Privacy & Security).

With a free Apple ID the app expires after 7 days; just run it from Xcode again. Use a real device: the Simulator's photo library is tiny and some Vision requests don't run there.

## Tuning

- **Similarity slider.** *Strict* only groups near-identical frames. *Loose* also groups the same scene from slightly different angles. If unrelated photos get lumped together, move it toward Strict. If obvious duplicates aren't grouped, move it toward Loose.
- **Time window.** Photos further apart than this are never grouped.
- **Keep best portrait and landscape.** Off by default.
- Weights live in `PhotoPicker/PhotoRanker.swift`.

## Code map

| File | What it does |
|---|---|
| `PhotoLibrary.swift` | Photos permission, fetching, image loading, deletion |
| `PhotoAnalyzer.swift` | Per-photo Vision requests (faces, pets, saliency, feature print), subject sharpness and exposure |
| `SimilarityGrouper.swift` | Clusters near-duplicates by time and feature-print distance |
| `PhotoRanker.swift` | Scores and orders photos within a group; close calls, tie-breaks and orientation picks |
| `ScanModel.swift` | Drives a scan and holds results |
| `ContentView.swift`, `ResultsView.swift`, `GroupDetailView.swift` | SwiftUI screens |
