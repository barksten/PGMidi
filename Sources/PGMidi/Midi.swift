//
//  Midi.swift
//  PGMidi
//
//  Created by Anders Östlin on 2015-02-17.
//
//

import Foundation

extension PGMidi {
    
    func findSourceCalled(name: String) -> PGMidiSource? {
        for source in self.sources {
            if source.name == name {
                return source as? PGMidiSource
            }
        }
        return nil
    }
    
    func findDestinationCalled(name: String) -> PGMidiDestination? {
        for destination in self.destinations {
            if destination.name == name {
                return destination as? PGMidiDestination
            }
        }
        return nil
    }
    
    func findMatchingSource(inout source: PGMidiSource?, inout andDestination destination: PGMidiDestination?,  avoidNames namesToAvoid: [String]?) {
        
        source = nil
        destination = nil
        
        for s in self.sources {
            if (s.isNetworkSession == true) {
                continue
            }
            
            if let namesToAvoid = namesToAvoid {
                for name in namesToAvoid {
                    if name == s.name {
                        continue
                    }
                }
                if let d = self.findDestinationCalled(s.name) {
                    source = s as? PGMidiSource
                    destination = d
                    return
                }
            }
        }
    }

    func findMatchingSource(inout source: PGMidiSource?, inout andDestination destination: PGMidiDestination?) {
        self.findMatchingSource(&source, andDestination: &destination, avoidNames: nil)
    }
}