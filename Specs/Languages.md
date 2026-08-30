# Languages

Selecting the languages to recognise, how speech is matched against them, and
what happens to speech in a language that is not selected.

## Selects and deselects languages

1. Open **Settings… → Languages**.
2. Observe **Selected Languages**.
3. Type "pol" into the search field.
4. Tick Polish in the list below.
5. Clear the search and untick English.

Assert: the default selection on a fresh install is English and Polish.
Assert: each selected language appears as a chip under **Selected Languages**.
Assert: searching filters by both language name and code.
Assert: ticking a language adds its chip immediately.
Assert: unticking removes it.

## Refuses to leave no language selected

1. Open **Settings… → Languages** with a single language selected.
2. Try to untick that language.
3. Try to remove its chip under **Selected Languages**.

Assert: the language stays selected.
Assert: the chip offers no remove button when it is the only one.
Assert: **Selected Languages** never shows "No languages selected".

## Transcribes a selected language as itself

1. Select English and Polish.
2. Start dictation with TextEdit focused.
3. Say `sentence-pl`, pause, then say `sentence-en`.

Assert: the Polish utterance is inserted in Polish.
Assert: the English utterance is inserted in English.
Assert: neither is translated into the other.

## Polish is not turned into English

1. Select English and Polish.
2. Start dictation with TextEdit focused.
3. Say `dzien-dobry-pl`, pause, and repeat five times.

Assert: every insertion is Polish.
Assert: no insertion contains an English rendering such as "good morning" or
"good day".

## Transcribes a single selected language

1. Select Polish only.
2. Start dictation with TextEdit focused.
3. Say `sentence-pl`.

Assert: the utterance is inserted in Polish.

## Speech outside the selected languages stays inside them [to review]

1. Select English only.
2. Ensure **Translate unsupported languages** is off.
3. Start dictation with TextEdit focused.
4. Say `guten-tag-de`.

Assert: the inserted text is English.
Assert: no German text is inserted.

Selecting a language constrains the output language, so German speech with only
English selected is rendered as English. The result reads as a translation while
the translation setting is off, which is worth confirming as the intended
behaviour for someone who selected one language and then spoke another.

## Translates unsupported speech when the setting is on

1. Select English only.
2. Open **Settings… → General** and turn **Translate unsupported languages** on.
3. Start dictation with TextEdit focused.
4. Say `guten-tag-de`.

Assert: the inserted text is an English translation of the German.
Assert: no engine reload happens when the setting is toggled — dictation stays
active.
Assert: turning the setting off again and repeating the utterance still produces
English, since English is the only selected language.

## Translation does not affect selected languages

1. Select English and Polish.
2. Turn **Translate unsupported languages** on.
3. Start dictation with TextEdit focused.
4. Say `sentence-pl`.

Assert: the utterance is inserted in Polish.
Assert: it is not translated into English.

## Chooses between selected languages by likelihood

1. Select English and Polish.
2. Start dictation with TextEdit focused.
3. Say `sentence-pl`, pause, then say `sentence-en`, pause, then say
   `bonjour-fr`.

Assert: the Polish utterance is inserted in Polish.
Assert: the English utterance is inserted in English.
Assert: the French utterance is inserted in whichever of English or Polish the
model scores higher, not in a fixed one of the two.

## Two languages in one utterance

1. Select English and Polish.
2. Start dictation with TextEdit focused.
3. Say `mixed-en-pl` as one utterance.

Assert: a single insertion arrives.
Assert: the insertion is in one of the two selected languages.

## Changing the language selection reloads the engine

1. Start dictation and confirm the active state.
2. Open **Settings… → Languages** and tick three more languages in quick
   succession.
3. Watch the menu bar icon.

Assert: the engine reloads once rather than once per language.
Assert: the reload starts about a second after the last change.

## Dictation does not resume after a language change [to review]

1. Start dictation and confirm the active state in the menu bar.
2. Open **Settings… → Languages** and change the selection.
3. Wait for the reload to finish and look at the menu bar icon.

Assert: dictation is active after the reload, or the user is told it stopped.

The engine returns to idle after reloading and dictation stays off. The only
indication is the menu bar icon changing back to the idle state.

## Language selection survives a restart

1. Select a distinctive set of languages, such as German and Japanese.
2. Quit Overhear and open it again.
3. Open **Settings… → Languages**.

Assert: the same set is selected.
Assert: the chips match the selection made before quitting.
