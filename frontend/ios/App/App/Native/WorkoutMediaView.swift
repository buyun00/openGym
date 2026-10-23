import SwiftUI
import AVFoundation
import UIKit

struct WorkoutMediaView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var record: WorkoutCatalogueRecord?
    var minimize: (() -> Void)? = nil
    @State private var playing = true
    @State private var visible = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if let url = record?.mediaURL(animated: true) {
                WorkoutLoopPlayer(url: url, playing: playing && visible && scenePhase == .active)
            } else { WorkoutThumbnail(record: record) }
            HStack {
                if let minimize {
                    Button("缩小", systemImage: "arrow.down.right.and.arrow.up.left", action: minimize).buttonStyle(.glass)
                }
                Spacer()
                if record?.mediaURL(animated: true) != nil {
                    Button(playing ? "点按暂停" : "点按播放", systemImage: playing ? "pause.fill" : "play.fill") { playing.toggle() }
                        .buttonStyle(.glass)
                }
            }.font(.caption).padding(10)
        }
        .aspectRatio(1.22, contentMode: .fit)
        .background(.white).clipShape(.rect(cornerRadius: 20))
        .onAppear { visible = true; playing = !reduceMotion }
        .onDisappear { visible = false }
        .onChange(of: reduceMotion) { _, reduced in if reduced { playing = false } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(record?.name ?? "动作")演示")
    }
}

struct WorkoutThumbnail: View {
    var record: WorkoutCatalogueRecord?
    var body: some View {
        Group {
            if let url = record?.mediaURL(animated: false), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "figure.strengthtraining.traditional").font(.largeTitle)
                    Text("暂无动作演示").font(.caption)
                }.foregroundStyle(.gray).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.background(.white)
    }
}

// AVQueuePlayer/AVPlayerLooper keep the actual bundled demonstration looping. UIKit owns
// video rendering; the transport buttons above are native SwiftUI Liquid Glass controls.
private struct WorkoutLoopPlayer: UIViewRepresentable {
    var url: URL
    var playing: Bool
    func makeUIView(context: Context) -> WorkoutPlayerSurface { WorkoutPlayerSurface() }
    func updateUIView(_ view: WorkoutPlayerSurface, context: Context) { view.update(url: url, playing: playing) }
    static func dismantleUIView(_ view: WorkoutPlayerSurface, coordinator: ()) { view.stop() }
}

private final class WorkoutPlayerSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var source: URL?
    override init(frame: CGRect) {
        super.init(frame: frame)
        (layer as? AVPlayerLayer)?.player = player
        (layer as? AVPlayerLayer)?.videoGravity = .resizeAspect
        player.isMuted = true
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(url: URL, playing: Bool) {
        if source != url {
            stop()
            source = url
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        }
        if playing { player.play() } else { player.pause() }
    }
    func stop() { player.pause(); looper?.disableLooping(); looper = nil; player.removeAllItems(); source = nil }
}
