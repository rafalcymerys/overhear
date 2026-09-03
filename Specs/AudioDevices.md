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

## Picks dictation back up when the device returns

1. From the previous scenario, plug the microphone back in within half a
   minute.
2. Say `HelloEn` without touching the menu.

Assert: dictation starts again on its own.
Assert: the utterance is transcribed.
Assert: the app does not need restarting.
Assert: nothing spoken while the device was away is transcribed — the batch
interrupted by the loss is gone, not resumed.

## Stays stopped when the device is gone for a while

1. From the same scenario, leave the microphone unplugged for a minute.
2. Plug it back in.

Assert: dictation does not start on its own.
Assert: the microphone is not opened until the user asks for it.
Assert: **Start Listening** works as usual.

The resumption is for a device changing under someone who is still dictating,
not for a Mac being come back to. Half a minute is long enough for a switch and
short enough that the microphone never opens unprompted once the user has gone.

## Does not pick up dictation that was already stopped

1. Stop dictation.
2. Change the system default input.

Assert: dictation stays stopped.
Assert: nothing opens the microphone.

## Switching the default input mid-session

1. Start dictation with the built-in microphone.
2. Change the system default input to another device in System Settings.
3. Say `HelloEn` once the new device is in use.

Assert: dictation stops when the device changes, then starts again on the new
device without the menu being touched.
Assert: the utterance is transcribed.
Assert: connecting or removing AirPods is such a change, in either direction.

## Stopping while the device is away is respected

1. Start dictation and unplug the microphone.
2. While it is unplugged, choose **Stop Listening**.
3. Plug the microphone back in.

Assert: dictation does not start again.
Assert: the intention to resume is dropped by the user stopping, not kept
waiting behind it.

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
Assert: the menu offers **Finish Setup…**.
Assert: restoring the permission allows dictation to start again.
