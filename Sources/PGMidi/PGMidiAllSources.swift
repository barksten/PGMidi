//
//  PGMidiAllSources.swift
//  PGMidi
//
//  Created by Anders Östlin on 2015-02-13.
//
//

import Foundation

@objc(PGMidiAllSources) class MidiAllSources: PGMidiDelegate, PGMidiSourceDelegate {
    var delegate: PGMidiSourceDelegate?
    var midi: PGMidi {
        get {
            return self.midi
        }
        set(newValue) {
            // clean up old value
            self.midi.delegate = nil
            for object in self.midi.sources as [AnyObject] {
                if let source = object as? PGMidiSource {
                    source.removeDelegate(self)
                }
            }
            // setup new value
            self.midi = newValue
            self.midi.delegate = self
            
            for object in self.midi.sources as [AnyObject] {
                if let source = object as? PGMidiSource {
                    source.addDelegate(self)
                }
            }
        }
    }
    
    //MARK: PGMidiDelegate
    
    func midi(midi: PGMidi, sourceAdded source: PGMidiSource) {
        source.addDelegate(self)
    }
    
    func midi(midi: PGMidi, sourceRemoved source: PGMidiSource) {
    }
    func midi(midi: PGMidi, destinationAdded destination: PGMidiDestination) {
    }
    func midi(midi: PGMidi, destinationRemoved destination: PGMidiDestination) {
    }

    //MARK: PGMidiSourceDelegate

    func midiSource(input: PGMidiSource, midiReceived packetList: UnsafePointer<MIDIPacketList>) {
        self.delegate?.midiSource(input, midiReceived:packetList)
    }
}