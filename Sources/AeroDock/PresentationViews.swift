import SwiftUI

struct ScriptEditorView: View {
    @ObservedObject var model: IslandModel
    @FocusState private var editing: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR WORDS, NEAR THE CAMERA").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.mint)
            Text("Paste your speech. Play advances through short cards while you present.").font(.system(size: 11)).foregroundStyle(.gray).fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $model.scriptText)
                .font(.system(size: 13)).scrollContentBackground(.hidden)
                .padding(8).frame(height: 115).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                .focused($editing).accessibilityLabel("Presentation script")
                .onChange(of: editing) { _, value in model.scriptEditing = value }
                .onChange(of: model.scriptText) { _, value in UserDefaults.standard.set(value, forKey: "presentationScript") }
            HStack {
                Text("Pace").font(.system(size: 11))
                Slider(value: $model.presentation.wordsPerMinute, in: 60...220, step: 10).accessibilityLabel("Reading speed")
                Text("\(Int(model.presentation.wordsPerMinute)) wpm").font(.system(size: 10)).monospacedDigit().frame(width: 55)
            }
            HStack {
                Text("Text size").font(.system(size: 11))
                Slider(value: $model.scriptFontSize, in: 18...32, step: 1).accessibilityLabel("Script text size")
            }
            Button("Play presentation") { editing = false; model.startPresenting() }
                .buttonStyle(MintButtonStyle())
                .disabled(model.scriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.padding(15).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 19))
        .onDisappear { model.scriptEditing = false }
    }
}

struct TeleprompterView: View {
    @ObservedObject var model: IslandModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("PRESENTING", systemImage: "text.alignleft").font(.system(size: 10, weight: .bold)).foregroundStyle(.mint)
                Spacer()
                if model.recorder.recording {
                    Button { model.recorder.stop() } label: { Label(model.recorder.time, systemImage: "stop.circle.fill").foregroundStyle(.red) }
                        .buttonStyle(.plain).help("Stop & save recording")
                }
                Text("\(model.presentation.index + 1) / \(model.presentation.cards.count)").font(.system(size: 10)).foregroundStyle(.gray)
                Button("Edit") { model.stopPresenting() }.buttonStyle(.plain).font(.system(size: 11))
            }
            ScrollViewReader { proxy in
            ScrollView {
                Text(model.presentation.current).font(.system(size: model.scriptFontSize, weight: .medium))
                    .lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading)
                    .id(model.presentation.index)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: model.presentation.index) { _, value in proxy.scrollTo(value, anchor: .top) }
            }
            ProgressView(value: model.presentation.progress).tint(.mint)
            HStack(spacing: 18) {
                Button { model.presentation.move(-1) } label: { Image(systemName: "backward.end.fill") }
                    .disabled(model.presentation.index == 0).accessibilityLabel("Previous passage")
                Button {
                    if model.presentation.running { model.presentation.pause() }
                    else { model.presentation.play(now: Date()) }
                } label: {
                    Label(model.presentation.running ? "Pause" : (model.presentation.finished ? "Replay" : "Play"), systemImage: model.presentation.running ? "pause.fill" : "play.fill")
                }.keyboardShortcut(.space, modifiers: [])
                Button { model.presentation.move(1) } label: { Image(systemName: "forward.end.fill") }
                    .disabled(model.presentation.index + 1 >= model.presentation.cards.count).accessibilityLabel("Next passage")
                Spacer()
                Button("−") { model.presentation.wordsPerMinute = max(60, model.presentation.wordsPerMinute - 10) }.help("Read slower")
                Text("\(Int(model.presentation.wordsPerMinute)) wpm").font(.system(size: 10)).monospacedDigit()
                Button("+") { model.presentation.wordsPerMinute = min(220, model.presentation.wordsPerMinute + 10) }.help("Read faster")
            }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.mint)
        }.padding(20)
    }
}

struct RecorderMenu: View {
    @ObservedObject var recorder: VoiceRecorder
    let show: () -> Void
    var body: some View {
        Divider()
        Button("Voice recorder…", action: show)
        if recorder.recording { Button("Stop & save recording (\(recorder.time))") { recorder.stop() } }
    }
}
struct RecordingStatus: View {
    @ObservedObject var recorder: VoiceRecorder
    var body: some View {
        HStack {
            Image(systemName: recorder.recording ? "record.circle.fill" : "rectangle.topthird.inset.filled")
                .symbolRenderingMode(.palette).foregroundStyle(recorder.recording ? .red : .primary)
            if recorder.recording { Text(recorder.time).monospacedDigit() }
        }.accessibilityLabel(recorder.recording ? "AeroDock recording \(recorder.time)" : "AeroDock")
    }
}
