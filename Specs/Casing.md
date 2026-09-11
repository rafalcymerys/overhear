# Casing

A transcription arrives as a sentence: capital at the front, full stop at the
end. That is right when dictation lands in an empty field and wrong the moment
it lands halfway through something the user was already writing, where a
capital in the middle of a line reads as a mistake rather than as speech.
**Match the case of the current sentence** decides whether Overhear re-cases
what it inserts to suit the sentence it is joining.

The setting lives in **Settings… → General**, under the **Transcription**
heading alongside **Strip transcription annotations** and **Ensure spaces
around inserted text**, and is on for a fresh install. Filtering runs first:
what casing sees is the text that is about to be inserted, once annotations
have been taken out of it — `Specs/TranscriptionOutput.md`. Spacing runs after,
on the text casing has already settled — `Specs/Spacing.md`.

The rule, in one place, so the scenarios below can be read against it:

- **One character.** Only the first character of the insertion that carries a
  case is ever changed. Leading whitespace and opening brackets and quotes are
  stepped over to find it. If what is found first is a digit, a symbol, or a
  character from a script with no case, nothing is changed at all.
- **Continuing.** When the caret sits inside a sentence, that character is
  lowercased.
- **Starting.** When the caret sits where a sentence begins, it is uppercased.
- **Where a sentence begins.** Read back from the caret, stepping over spaces
  and tabs, over closing brackets and the single quotes — `)` `]` `}` `”` `'`
  `’` — and over opening brackets `(` `[` `{`, which say nothing either way. A
  sentence begins at: nothing at all, the start of the field; a newline; `.`
  `!` `?` `…`; their fullwidth counterparts `。` `！` `？`; the Spanish `¿` and
  `¡`, which open the sentence they mark; and a double quote, `"` or `“`.
  Everything else is mid-sentence — a letter, a digit, `,` `;` `:` and a dash
  among them.
- **The double quote is read as a boundary from either end.** Nothing in the
  field says which end of a pair a `"` is, and it does not have to: `He said "`
  opens a quotation and wants a capital, and `He said "Hello." ` has a full
  stop one step further back and wants one too. The single quotes go the other
  way for the same reason — they are apostrophes more often than quotation
  marks, and `the dogs' ` continues its sentence.
- **Words that keep their case.** An acronym, meaning a first word of two or
  more characters written entirely in capitals. A word with a capital inside it
  but not at the front, such as `iPhone`. The English `I`, alone or contracted
  — `I'm`, `I'll`, `I've`, `I'd`.
- **Nothing else moves.** The rest of the transcription is untouched, and text
  already in the field is never edited — Overhear cases what it is inserting,
  not what it is inserting next to.
- **Read, not remembered.** The sentence is read from the field at the moment
  of insertion rather than from what Overhear inserted last, so a user who
  types or moves the caret between utterances gets the case the caret asks for.
- **Unreadable surroundings.** When the text around the caret cannot be read,
  the insertion is capitalised. There is no sentence to match, and a capital is
  what a transcription arrives with anyway.

Every scenario is with the setting on unless it says otherwise. Quoted field
contents write the caret as `|`, and a space that has to be counted as `·`.

## The setting sits with the transcription settings

1. Open **Settings… → General** on a fresh install.

Assert: **Match the case of the current sentence** is offered under the
**Transcription** heading, below **Ensure spaces around inserted text**.
Assert: it is on.
Assert: its explanation sits inside the same group box as its checkbox, the way
the other two transcription settings' do.
Assert: the explanation says what it does in one sentence, reading "When
dictating into the middle of a sentence, continue it in lower case; when
there's nothing to continue, capitalise what you've just dictated."
Assert: it is stored and restored with every other setting —
`Specs/Settings.md`.

## Continues a half-written sentence

1. In TextEdit, type `The fox jumps over ` and leave the caret after the space:
   `over·|`.
2. Start dictation and say `HelloEn`.

Assert: the document reads `The fox jumps over hello.` — the capital the model
transcribed is gone.
Assert: the full stop the model transcribed is still there. Casing changes the
front of the insertion and nothing else.
Assert: the existing text is otherwise untouched — `over` is not recapitalised,
and nothing before the caret is rewritten.

## Leaves a new sentence capitalised

1. In TextEdit, type `The fox jumps.` and leave the caret after the full stop.
2. Start dictation and say `HelloEn`.

Assert: the document reads `The fox jumps.·Hello.` — the capital stays.
Assert: the same holds with the caret after `!`, after `?`, and after `…`.
Assert: the same holds with a space between the full stop and the caret, and
with two spaces: reading back steps over them.

## Capitalises a transcription that arrives lowercase

1. Focus an empty TextEdit document.
2. Start dictation and say an utterance the model transcribes without a leading
   capital — a continuation after a pause is the usual way to get one.

Assert: the inserted text begins with a capital.
Assert: only the first letter is changed; the rest of the sentence keeps the
case the model gave it.
Assert: no word other than the first is capitalised — this is not title case.

## Capitalises in an empty field

1. Focus an empty TextEdit document.
2. Start dictation and say `SentenceEn`.

Assert: the insertion begins with a capital.
Assert: the same holds for an empty browser text field and an empty Notes note.
Assert: the same holds at the start of a document that already has text after
the caret: `|the fox jumps` gets a capitalised insertion.
Assert: the `the` that follows is left lowercase. Overhear does not edit what
is already there, even when the result reads oddly.

## A new line starts a new sentence

1. In TextEdit, type `The fox jumps over` and press Return, leaving the caret at
   the start of the empty second line.
2. Start dictation and say `HelloEn`.

Assert: the insertion is capitalised, though the line above ends without
punctuation.
Assert: the same holds after a blank line.
Assert: the same holds with the caret at the start of a line that has text
after it on the same line.

A line break is how someone writes a new paragraph, a new list item or a new
cell, and none of those continue the sentence above them.

## Reads back past closing punctuation

1. In TextEdit, type `He said “The fox jumps.” ` and leave the caret after the
   trailing space.
2. Start dictation and say `HelloEn`.

Assert: the insertion is capitalised — reading back steps over the closing
quote to find the full stop.
Assert: the same holds after `)`, `]` and `}` following a full stop.
Assert: the same holds with straight quotes, `He said "The fox jumps." `,
though by the other half of the rule: a `"` is a boundary in its own right.
Assert: `The fox (jumps) ` — a closing bracket with a letter before it — gets a
lowercased insertion, because what the step back finds is `s`.

## Opens a quotation with a capital

1. In TextEdit, type `He said "` and leave the caret after the quote.
2. Start dictation and say `HelloEn`.

Assert: the insertion is capitalised.
Assert: the same holds after `“`.
Assert: a single quote does not do this: `the dogs' |` and `the dogs’ |` get a
lowercased insertion, because a single quote is an apostrophe more often than
it is a quotation mark, and nothing in the field says which. It is read past
rather than read as a boundary, so what decides is the `s` in front of it.

## Opening brackets say nothing either way

1. In TextEdit, type `The fox jumps (` and leave the caret after the bracket.
2. Start dictation and say `HelloEn`.

Assert: the insertion is lowercased — reading back steps over the bracket and
finds `s`, so this is a parenthetical inside a sentence.
Assert: `The fox jumps. (|` gets a capitalised insertion.
Assert: `(|` at the very start of an empty document gets a capitalised one.
Assert: the same holds for `[` and `{`.

## Spanish opening marks start a sentence

1. Select Spanish — `Specs/Languages.md`.
2. In TextEdit, type `¿` and leave the caret after it.
3. Start dictation and say `SentenceEs`.

Assert: the document reads `¿Estoy muy bien, gracias.` — the insertion is
capitalised.
Assert: the same holds after `¡`.
Assert: the mark is not treated as ordinary punctuation to be read past — it
opens the sentence it marks rather than sitting inside one.
Assert: the same utterance with the caret after `Dijo que ` instead arrives as
`Dijo que estoy muy bien, gracias.` Both cases are the rule working; what `¿`
changes is which way it decides.

## Mid-sentence punctuation does not start a sentence

1. In TextEdit, type `The fox jumps, ` and leave the caret after the space.
2. Start dictation and say `HelloEn`.

Assert: the insertion is lowercased.
Assert: the same holds after `;`, after `:`, after `-`, and after an em dash.
Assert: the same holds after a digit: `I counted 3 ` gets a lowercased
insertion.

A colon introduces as often as it concludes, and prose that capitalises after
one is the exception. It is read as mid-sentence.

## Inserts inside a word

1. In TextEdit, type `Hello` and place the caret between the `l` and the `o`:
   `Hell|o`.
2. Start dictation and say `HelloEn`.

Assert: the insertion is lowercased, by the same rule as any other letter
before the caret.
Assert: nothing tries to keep the word whole — the rule reads the characters
around the caret, not the words.

## Acronyms keep their capitals

1. In TextEdit, type `I heard that ` and leave the caret after the space.
2. Start dictation and say `AcronymEn`.

Assert: the document reads `I heard that NASA hired her.` — the acronym keeps
all four capitals rather than arriving as `nASA`.
Assert: `hired her` is untouched.
Assert: a first word of a single capital letter is not treated as an acronym:
an insertion beginning `A dog ran.` becomes `a dog ran.`
Assert: a word with a capital inside it but not at the front keeps its case in
both directions — `iPhone` stays `iPhone` mid-sentence, and stays `iPhone` at
the start of a sentence rather than becoming `IPhone`.

## The English I keeps its capital

1. In TextEdit, type `She left because ` and leave the caret after the space.
2. Start dictation and say `PronounEn`.

Assert: the document reads `She left because I was late.` — the pronoun keeps
its capital.
Assert: the same holds for `I'm`, `I'll`, `I've` and `I'd`.
Assert: a word merely beginning with `I` is not spared: `It was late.` becomes
`it was late.`

## Only the first character changes

1. In TextEdit, type `The fox jumps over ` and leave the caret after the space.
2. Start dictation and say `SentenceEn`.

Assert: the document reads `The fox jumps over the quick brown fox jumps over
the lazy dog.`
Assert: no capital anywhere else in the insertion is touched.
Assert: an insertion containing a proper noun keeps that noun's capital.
Assert: an insertion containing a second sentence keeps that sentence's
capital — casing looks at the front of what it is given, not at every sentence
inside it.

## Leading punctuation is stepped over

1. In TextEdit, type `He said ` and leave the caret after the space.
2. Start dictation and say an utterance the model transcribes with a leading
   quotation mark, such as `"Hello," he said.`

Assert: the character cased is the first letter, not the quotation mark: the
insertion reads `"hello," he said.`
Assert: an insertion arriving with a leading space is cased at its first letter
too, and keeps its space.
Assert: an insertion beginning with `(` or `[` is treated the same way.

## Text with no case is left alone

1. In TextEdit, type `The fox jumps. ` and leave the caret after the space.
2. Start dictation and say `NumberEn`.

Assert: the document reads `The fox jumps. 1999 was a good year.` — the `w` is
not capitalised.
Assert: nothing is capitalised further into the text in search of a letter.
Assert: an insertion beginning with a symbol or an emoji is left alone the same
way.

Hunting past a digit for something to capitalise would turn `1999 was a good
year` into `1999 Was a good year`. The first thing the insertion leads with is
the thing that decides, and a number decides nothing.

## Chinese has no case to match

1. Select Chinese — `Specs/Languages.md`.
2. In TextEdit, type `你好` and leave the caret after it.
3. Start dictation and say `SentenceZh`.

Assert: the insertion is unchanged.
Assert: the same holds for Japanese and Thai.
Assert: English inserted after `你好。` is capitalised — the fullwidth full stop
ends a sentence the way `.` does.
Assert: English inserted after `你好` with no full stop is lowercased.

## Other languages capitalise differently

1. Select German — `Specs/Languages.md`.
2. In TextEdit, type `Ich sehe den ` and leave the caret after the space.
3. Start dictation and say `NounDe`.

Assert: the document reads `Ich sehe den hund im Garten.` — the opening noun is
lowercased, which German spelling does not want.
Assert: `Garten` keeps its capital. Only the first character is ever cased, so
the rest of the sentence is as German as the model wrote it.
Assert: with the setting off, the same utterance arrives as `Ich sehe den Hund
im Garten.`
Assert: the `I` carve-out is just as English: select Polish, type
`Naciskam przycisk, ` and say `ConjunctionPl`, and the document reads
`Naciskam przycisk, I tak to działa.` where Polish wants a lowercase `i`.

The rule is about sentence position, and it is applied the same way whatever
language was transcribed. Making it language-aware would mean knowing which
language the utterance was in and carrying a rule per language, which is more
than a case fix is worth; the user fixes the letter as they would fix any other
word the model got wrong.

## Abbreviations look like sentence ends

1. In TextEdit, type `We need milk, eggs, etc. ` and leave the caret after the
   space.
2. Start dictation and say `ContinuationEn`.

Assert: the document reads `We need milk, eggs, etc. And some bread.` — the
capital stays, though the sentence has not ended.
Assert: placing the caret after `eggs, ` instead and saying the same utterance
gets `We need milk, eggs, and some bread.` A comma says mid-sentence with no
ambiguity, and there the rule lowercases as it should.
Assert: the same unwanted capital appears after `e.g. `, after `Dr. ` and after
an initial such as `J. `.

Telling an abbreviation from a full stop needs a dictionary, and the cost of
being wrong runs the other way too: refusing to capitalise after a genuine full
stop is the more visible error of the two.

## Replaces a selection

1. In TextEdit, type `The fox jumps over the dog.` and select the word `fox`.
2. Start dictation and say `HelloEn`.

Assert: the selection is replaced by the transcription.
Assert: the case is decided from the text before the selection, not from the
selected text: `The ` precedes it, so the insertion is lowercased.
Assert: selecting `The` at the very start of the document gets a capitalised
insertion — what matters is that nothing precedes the selection, not that the
selected word was capitalised.
Assert: selecting the whole document gets a capitalised insertion.

## Follows the caret rather than the last insertion

1. Start dictation with an empty TextEdit document focused.
2. Say `HelloEn` and wait for the insertion.
3. Say `HelloEn` again.
4. Move the caret to the start of the document and say `HelloEn` a third time.

Assert: the second insertion is capitalised — the first ended with a full stop,
so the second starts a sentence.
Assert: the third is capitalised too, because nothing precedes it.
Assert: typing `, ` at the end of the document and dictating again gets a
lowercased insertion — the field is read, not what Overhear did last.
Assert: switching to another application between utterances cases against that
application's field.

## Several utterances in a row

1. Start dictation with an empty TextEdit document focused.
2. Say `HelloEn`, pause two seconds.
3. Say `SentenceEn`, pause two seconds.
4. Say `HelloEn`, pause two seconds.

Assert: all three insertions are capitalised, each following the previous
sentence's full stop.
Assert: the sentences themselves are otherwise unchanged.
Assert: with **Ensure spaces around inserted text** on as well, the three are
separated by one space each and each begins with a capital.

## Works with spacing off

1. Open **Settings… → General** and turn **Ensure spaces around inserted text**
   off, leaving **Match the case of the current sentence** on.
2. In TextEdit, type `The fox jumps over ` and leave the caret after the space.
3. Start dictation and say `HelloEn`.

Assert: the insertion is lowercased.
Assert: no space is added — the two settings are independent, and neither needs
the other to do its work.
Assert: the reverse combination works too: with casing off and spacing on, the
insertion is spaced and its capital is left alone.
Assert: with both off, the transcription is inserted exactly as transcribed.

## An utterance that filters away leaves nothing behind

1. Confirm **Strip transcription annotations** is on.
2. In TextEdit, type `Hello` and leave the caret after it.
3. Start dictation and say `Coughing`.

Assert: nothing at all is inserted.
Assert: the document still reads `Hello`.
Assert: dictation stays active.

Casing runs on what is about to be inserted. With nothing to insert there is
nothing to case, and the setting must not turn a dropped annotation into a
visible edit.

## Pasting a recent transcription

1. Dictate two utterances so both are listed under **Last Transcriptions**.
2. In TextEdit, type `The fox jumps over ` and leave the caret after the space.
3. Open the menu bar menu and click the second entry.

Assert: the entry is inserted lowercased, by the same rule as a live
transcription.
Assert: the entry in the menu is unchanged — the case is decided on the way
into the document, not stored with the transcription.
Assert: **Last Transcriptions** shows every entry as transcribed, so the same
entry pasted into an empty document arrives capitalised.

## An application that does not expose its text

1. Start dictation and focus Terminal at a prompt with a partly typed command.
2. Say `HelloEn`.

Assert: the transcription is inserted capitalised, rather than lowercased on a
guess about what precedes it.
Assert: no error is shown and dictation stays active.
Assert: the same holds in any other field whose contents Overhear cannot read,
including a password field and a canvas-drawn editor in a browser.

A capital is what the transcription arrived with. Falling back to it means an
unreadable field gets exactly what it would have got before this setting
existed.

## An Electron application

1. Start dictation and focus the message box in Slack, or another Electron
   application, with `The fox jumps over ` typed and the caret after the space.
2. Say `HelloEn` and wait for the insertion.
3. Say `HelloEn` again.

Assert: the second insertion is lowercased.
Assert: the first is lowercased too, or inserted capitalised — Chromium builds
the accessibility tree only once it is asked to, and the asking and the reading
happen in the same breath — `Specs/Spacing.md`.
Assert: nothing is asked of the user, and no permission dialog appears.
Assert: the application is asked once — a third and fourth utterance are cased
like the second.

## One paste, one undo

1. In TextEdit, type `The fox jumps over ` and leave the caret after the space.
2. Start dictation, say `HelloEn`, and wait for the insertion.
3. Press Cmd+Z once.

Assert: the whole insertion disappears, cased text and all.
Assert: the document is back to `The fox jumps over `, with nothing left behind
and nothing recapitalised.
Assert: one more Cmd+Z undoes what was typed in step 1.
Assert: the clipboard is restored as it always is, and carries the cased text
rather than the raw transcription while it holds it —
`Specs/TranscriptionOutput.md`.

## Off inserts exactly what was transcribed

1. Open **Settings… → General** and turn **Match the case of the current
   sentence** off.
2. In TextEdit, type `The fox jumps over ` and leave the caret after the space.
3. Start dictation and say `HelloEn`.

Assert: the document reads `The fox jumps over Hello.` — the capital is left
where the model put it.
Assert: a transcription that arrives lowercase in an empty field is not
capitalised either. The setting is off in both directions, not only the one.
Assert: nothing else about the insertion changes.

## Turning it on takes effect on the next utterance

1. With the setting off, dictate into a half-written sentence and see the
   capital arrive.
2. Open **Settings… → General** and turn **Match the case of the current
   sentence** on, leaving dictation running.
3. Say `HelloEn` again.

Assert: the second insertion is lowercased.
Assert: no engine reload happens and dictation is not interrupted.
Assert: the insertion already in the document is not retrospectively changed.
Assert: turning it off again takes effect on the next utterance the same way.
