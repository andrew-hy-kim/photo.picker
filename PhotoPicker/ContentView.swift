import SwiftUI

struct ContentView: View {
    @Bindable var model: ScanModel

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .idle:
                    ScanSetupView(model: model)
                case let .scanning(done, total):
                    ScanProgressView(done: done, total: total, onCancel: { model.cancelScan() })
                case .grouping:
                    ProgressView("Finding similar shots…")
                case .results:
                    ResultsView(model: model)
                case let .failed(message):
                    ContentUnavailableView {
                        Label("Couldn't scan", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Back") { model.reset() }
                    }
                }
            }
            .navigationTitle("Photo Picker")
        }
    }
}

struct ScanSetupView: View {
    let model: ScanModel

    @State private var start = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
    @State private var end = Date.now
    @AppStorage("similarityThreshold") private var threshold = 0.55
    @AppStorage("maxTimeGapMinutes") private var gapMinutes = 5.0

    var body: some View {
        Form {
            Section {
                DatePicker("From", selection: $start, displayedComponents: .date)
                DatePicker("To", selection: $end, in: start..., displayedComponents: .date)
                HStack {
                    preset("7 days", days: 7)
                    preset("30 days", days: 30)
                    preset("1 year", days: 365)
                }
                .buttonStyle(.bordered)
            } header: {
                Text("Which photos?")
            } footer: {
                Text("Pick the dates of your trip. Everything is analysed on your iPhone — nothing is uploaded.")
            }

            Section {
                VStack(alignment: .leading) {
                    Text("Similarity: \(similarityLabel)")
                    Slider(value: $threshold, in: 0.3...0.8, step: 0.05) {
                        Text("Similarity")
                    } minimumValueLabel: {
                        Text("Strict").font(.caption)
                    } maximumValueLabel: {
                        Text("Loose").font(.caption)
                    }
                }
                Stepper("Within \(Int(gapMinutes)) min of each other", value: $gapMinutes, in: 1...60)
            } header: {
                Text("What counts as the same shot?")
            } footer: {
                Text("Strict only groups near-identical frames. Loose also groups the same scene from slightly different angles.")
            }

            Section {
                Button {
                    model.startScan(
                        from: Calendar.current.startOfDay(for: start),
                        to: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end))!,
                        options: GroupingOptions(maxTimeGap: gapMinutes * 60, similarityThreshold: Float(threshold))
                    )
                } label: {
                    Label("Find the best shots", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private var similarityLabel: String {
        switch threshold {
        case ..<0.45: "Strict"
        case ..<0.65: "Balanced"
        default: "Loose"
        }
    }

    private func preset(_ title: String, days: Int) -> some View {
        Button(title) {
            end = .now
            start = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        }
        .frame(maxWidth: .infinity)
    }
}

struct ScanProgressView: View {
    let done: Int
    let total: Int
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ProgressView(value: Double(done), total: Double(max(total, 1)))
            Text("Analysing \(done) of \(total) photos")
                .font(.headline)
            Text("Keep the app open. Photos stored only in iCloud take longer while they download.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Cancel", role: .cancel, action: onCancel)
        }
        .padding(32)
    }
}
