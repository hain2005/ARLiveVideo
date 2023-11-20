//
//  AudioManager.swift
//  ARLiveVideo
//
//  Created by HAI/T NGUYEN on 11/20/23.
//

import Foundation
import ARKit

class AudioManager : ObservableObject {
    var audioPlayer : AVAudioPlayer?
    
    func loadAudio(filename: String) {
        
        guard let audioData = NSDataAsset(name: filename)?.data else {
            return
        }
        do {
            audioPlayer = try AVAudioPlayer(data: audioData)
            audioPlayer?.numberOfLoops = -1
            
        } catch {
            print("[shark], audioPlayer cannot load",error)
        }
    }
    
    func playAudio() {
        audioPlayer?.play()
    }
    
    func pauseAudio() {
        audioPlayer?.pause()
    }
}
