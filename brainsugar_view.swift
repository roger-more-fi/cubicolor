//
//  brainsugar_view.swift
//  created by Harri Hilding Smatt on 2025-12-28
//

import AVFoundation
import SwiftUI

class UITap : UITouch {
    var location : CGPoint
    init(_ location : CGPoint) {
        self.location = location
        super.init()
    }
    override func location(in: UIView?) -> CGPoint {
        return self.location
    }
}

struct BrainsugarView : View {
    @State var globeImage: Image = Image(systemName: "globe")
    @State var renderView : BrainsugarRenderView
    @State var showRenderView : Bool = false
    var audioEngine : AVAudioEngine

    init() {
        let renderView = BrainsugarRenderView()
        self.renderView = renderView
        audioEngine = AVAudioEngine()
     }

    var body: some View {
        VStack {
            ZStack {
                if showRenderView {
                    renderView
                        .gesture(SpatialEventGesture()
                            .onChanged { events in
                                var tapPositions = Set<UITap>()
                                for event in events {
                                    if event.phase == .active {
                                        let uiTap = UITap(event.location)
                                        tapPositions.insert(uiTap)
                                    }
                                }
                                renderView.coordinator?.setTapPositions(tapPositions)
                            }
                            .onEnded { events in
                                renderView.coordinator?.setTapPositions(Set<UITouch>())
                            }
                        )
                        .aspectRatio(contentMode: .fill)
                        .edgesIgnoringSafeArea(.all)
                } else {
                    globeImage
                        .imageScale(.large)
                        .foregroundColor(.accentColor)
                }
            }
            VStack {
                Text("Hello, world!")
                    .frame(width: 200, height: 32, alignment: .top)
                if !showRenderView {
                    Button("Click me!") {
                        withAnimation {
                            showRenderView = true
                            start()
                        }
                    }
                }
            }
        }
        .contentMargins(0.0)
        .padding(EdgeInsets())
        .preferredColorScheme(showRenderView ? .light : .dark)
        .transition(.asymmetric(insertion: .opacity, removal: .slide))
    }
    
    func start() {
        do {
            _ = audioEngine.mainMixerNode
            audioEngine.prepare()
            try audioEngine.start()
            
            guard let audioUrl = Bundle.main.url(forResource: "brainsugar", withExtension: "mp3") else {
                print("mp3 not found")
                return
            }
            
            let player = AVAudioPlayerNode()
            let audioFile = try AVAudioFile(forReading: audioUrl)
            let format = audioFile.processingFormat
            
            audioEngine.attach(player)
            audioEngine.connect(player, to: audioEngine.mainMixerNode, format: format)
            
            player.scheduleFile(audioFile, at: nil, completionHandler: nil)
            player.play()
            
        } catch let error {
            print(error.localizedDescription)
        }
    }
}
