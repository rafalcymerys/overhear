# Languages

Selecting the languages to recognise, how speech is matched against them, and
what happens to speech in a language that is not selected.

The languages a model can recognise are a property of that model, so the
selection lives in the **Languages** row of the **Active Model** card in
**Settings… → Transcription**. The model itself is
`Specs/TranscriptionModel.md`.

## Selects and deselects languages

1. Open **Settings… → Transcription**.
2. Click the control in the **Languages** row.
3. Type "pol" into the search field at the top of the pull-down.
4. Tick Polish.
5. Clear the search and untick English.

Assert: the default selection on a fresh install is English and Polish, unless
an English-only model was chosen during setup, which narrows it to English.
Assert: the pull-down lists every language the active model supports, each with
its code.
Assert: the selected languages are ticked and sorted to the top.
Assert: searching filters by both language name and code.
Assert: the pull-down stays open as languages are ticked and unticked.
Assert: the row's summary updates with each tick.

## Summarises the selection on the closed control

1. Open **Settings… → Transcription** with English selected.
2. Add Polish, then add three more languages.
3. Close the pull-down after each change.

Assert: one language reads as its name, such as "English".
Assert: two read as both names, such as "English, Polish".
Assert: more than two are shortened, such as "English, Polish & 3 more".
Assert: the summary never widens the window.

## Refuses to leave no language selected

1. Open **Settings… → Transcription** with a single language selected.
2. Open the **Languages** pull-down and try to untick that language.

Assert: the language stays ticked.
Assert: the row never summarises the selection as "No languages selected".

## Dims what the active model cannot transcribe

1. Select English and Polish.
2. Activate Parakeet TDT 0.6B v2, which supports English only.
3. Open the **Languages** pull-down.

Assert: English is ticked and the languages the model cannot transcribe are
listed dimmed rather than hidden.
Assert: a dimmed language cannot be ticked.
Assert: the pull-down says the dimmed languages are unsupported by this model.
Assert: activating a multilingual model again restores Polish to the selection
without the user reselecting it.

## Transcribes a selected language as itself

1. Select English and Polish.
2. Start dictation with TextEdit focused.
3. Say `SentencePl`, pause, then say `SentenceEn`.

Assert: the Polish utterance is inserted in Polish.
Assert: the English utterance is inserted in English.
Assert: neither is translated into the other.

## Polish is not turned into English

1. Select English and Polish.
2. Start dictation with TextEdit focused.
3. Say `DzienDobryPl`, pause, and repeat five times.

Assert: every insertion is Polish.
Assert: no insertion contains an English rendering such as "good morning" or
"good day".

## Transcribes a single selected language

1. Select Polish only.
2. Start dictation with TextEdit focused.
3. Say `SentencePl`.

Assert: the utterance is inserted in Polish.

## Speech outside the selected languages stays inside them [to review]

1. Select English only.
2. Ensure **Translate unsupported languages** is off.
3. Start dictation with TextEdit focused.
4. Say `GutenTagDe`.

Assert: the inserted text is English.
Assert: no German text is inserted.

Selecting a language constrains the output language, so German speech with only
English selected is rendered as English. The result reads as a translation while
the translation setting is off, which is worth confirming as the intended
behaviour for someone who selected one language and then spoke another.

## Translates unsupported speech when the setting is on

Whisper only. The setting sits under the languages row in the Active Model
card, and a model with no translate task leaves it unticked and disabled — see
`Specs/TranscriptionModel.md`.

1. Select English only.
2. Open **Settings… → Transcription** and turn **Translate unsupported
   languages** on, beneath the languages row.
3. Start dictation with TextEdit focused.
4. Say `GutenTagDe`.

Assert: the inserted text is an English translation of the German.
Assert: no engine reload happens when the setting is toggled — dictation stays
active.
Assert: turning the setting off again and repeating the utterance still produces
English, since English is the only selected language.

## Translation does not affect selected languages

1. Select English and Polish.
2. Turn **Translate unsupported languages** on.
3. Start dictation with TextEdit focused.
4. Say `SentencePl`.

Assert: the utterance is inserted in Polish.
Assert: it is not translated into English.

## Chooses between selected languages by likelihood

1. Select English and Polish.
2. Start dictation with TextEdit focused.
3. Say `SentencePl`, pause, then say `SentenceEn`, pause, then say
   `BonjourFr`.

Assert: the Polish utterance is inserted in Polish.
Assert: the English utterance is inserted in English.
Assert: the French utterance is inserted in whichever of English or Polish the
model scores higher, not in a fixed one of the two.

## Two languages in one utterance

1. Select English and Polish.
2. Start dictation with TextEdit focused.
3. Say `MixedEnPl` as one utterance.

Assert: a single insertion arrives.
Assert: the insertion is in one of the two selected languages.

## Changing the language selection reloads the engine

1. Start dictation and confirm the active state.
2. Open **Settings… → Transcription** and tick three more languages in the
   **Languages** pull-down in quick succession.
3. Watch the menu bar icon.

Assert: the engine reloads once rather than once per language.
Assert: the reload starts about a second after the last change.

## Dictation does not resume after a language change [to review]

1. Start dictation and confirm the active state in the menu bar.
2. Open **Settings… → Transcription** and change the selection.
3. Wait for the reload to finish and look at the menu bar icon.

Assert: dictation is active after the reload, or the user is told it stopped.

The engine returns to idle after reloading and dictation stays off. The only
indication is the menu bar icon changing back to the idle state.

## Language selection survives a restart

1. Select a distinctive set of languages, such as German and Japanese.
2. Quit Overhear and open it again.
3. Open **Settings… → Transcription**.

Assert: the same set is selected.
Assert: the row's summary matches the selection made before quitting.
