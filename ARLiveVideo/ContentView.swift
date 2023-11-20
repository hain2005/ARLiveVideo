//
//  ContentView.swift
//  ARLiveVideo
//
//  Created by HAI/T NGUYEN on 11/13/23.
//

import SwiftUI

struct ContentView : View {
    @State private var percentOfRed = 0
    @ObservedObject var audioManager = AudioManager()
    
    init() {
        audioManager.loadAudio(filename: "alert")
    }
    
    var body: some View {
        ZStack {
            ARViewContainer(percentOfRed: $percentOfRed)
            VStack {
                Spacer()
                Text("% of red \(percentOfRed)")
                    .font(.system(size: 36))
                    .foregroundColor(.white)
                    .padding(.bottom, 40)
                    .onChange(of: percentOfRed) { selection in
                        
                         if (percentOfRed > 50) {
                            audioManager.playAudio()
                        } else {
                            audioManager.pauseAudio()
                        }
                    }
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
}

#Preview {
    ContentView()
}
