# Audio Devices

How dictation behaves when the input device changes, disappears or is taken by
another application.

## Uses the system default input

1. Set a specific input device as the system default in System Settings.
2. Open Overhear and start dictation.
3. Say `HelloEn`.

Assert: the utterance is transcribed.
Assert: the macOS microphone indicator shows Overhear using the microphone.

## Losing the device stops dictation

1. Connect a USB microphone and make it the system default.
2. Start dictation and confirm the active state.
3. Unplug the microphone while dictation is active.
4. Wait five seconds.

Assert: dictation stops within a few seconds.
Assert: the menu bar icon returns to the idle state.
Assert: the overlay disappears.
Assert: no partial transcription is inserted.

## Recovers after the device returns

1. From the previous scenario, plug the microphone back in.
2. Wait five seconds.
3. Start dictation and say `HelloEn`.

Assert: the app does not need restarting.
Assert: the utterance is transcribed.

## Switching the default input mid-session

1. Start dictation with the built-in microphone.
2. Change the system default input to another device in System Settings.
3. Wait five seconds, then start dictation again and say `HelloEn`.

Assert: dictation stops when the device changes.
Assert: the new device is used afterwards.
Assert: the utterance is transcribed.

## Starting with no input device

1. Disconnect every input device, including disabling the built-in microphone
   if possible.
2. Open Overhear.
3. Wait ten seconds.

Assert: the app does not crash.
Assert: dictation does not report itself as ready.
Assert: connecting a device afterwards lets dictation start without relaunching.

## Speaking immediately after starting dictation

1. Ensure dictation is stopped.
2. Choose **Start Listening** and begin speaking `SentenceEn` within half a
   second.

Assert: the utterance is transcribed.
Assert: the opening word is not clipped.

## Microphone shared with another application

1. Start a call in another application that holds the microphone.
2. Start dictation in Overhear and say `HelloEn`.

Assert: the utterance is transcribed.
Assert: the other application keeps working.
Assert: the macOS microphone indicator stays on.

## Revoking microphone permission while running

1. Start dictation and confirm the active state.
2. Revoke Overhear's microphone access in System Settings.
3. Return to Overhear and open the menu bar menu.

Assert: dictation stops.
Assert: the menu offers **Grant Permissions…**.
Assert: restoring the permission allows dictation to start again.
