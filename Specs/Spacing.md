# Spacing

Dictation rarely lands in an empty field. It arrives at the end of a
half-written sentence, or in the middle of one the user has gone back to.
**Ensure spaces around inserted text** decides whether Overhear separates what it
inserts from what is already there.

The setting lives in **Settings… → General**, under the **Transcription**
heading alongside **Strip transcription annotations**, and is on for a fresh
install. Filtering runs first: what spacing sees is the text that is about to
be inserted, once annotations have been taken out of it —
`Specs/TranscriptionOutput.md`.

The rule, in one place, so the scenarios below can be read against it:

- **Before.** A space goes in unless there is nothing before the caret, the
  character before it is a space, a tab or a newline, or that character opens
  something: `(`, `[`, `{`, `"`, `'`, `“`, `‘`, `¿`, `¡`.
- **After.** A space goes in only when there is a character after the caret,
  and it is none of a space, a tab, a newline, or punctuation that attaches to
  the word in front of it: `.` `,` `;` `:` `!` `?` `)` `]` `}` `"` `'` `”` `’`.
- **Never twice.** Text that already begins or ends with whitespace keeps its
  own and is given no second one, and text beginning with attaching
  punctuation is given nothing before it.
- **Scripts that separate words without spaces.** Nothing is added between two
  characters of such a script — Chinese, Japanese, Thai.
- **Read, not remembered.** Both sides are read from the field at the moment
  of insertion rather than from what Overhear inserted last, so a user who
  types or moves the caret between utterances gets the spacing the caret asks
  for.
- **Unreadable surroundings.** When the text around the caret cannot be read,
  nothing is added on either side.

Every scenario is with the setting on unless it says otherwise. Quoted field
contents write the caret as `|`, and a space that has to be counted as `·`.

## The setting sits with the transcription settings

1. Open **Settings… → General** on a fresh install.

Assert: **Ensure spaces around inserted text** is offered under the
**Transcription** heading, below **Strip transcription annotations**.
Assert: it is on.
Assert: its explanation sits inside the same group box as its checkbox, the
way the other transcription setting's does.
Assert: the explanation says what it does in one sentence, reading "When
transcribing text next to an existing sentence, make sure that there is a
space around what you've just dictated."
Assert: it is stored and restored with every other setting —
`Specs/Settings.md`.

## Adds a space after existing text

1. In TextEdit, type `Hello` and leave the caret directly after the `o`:
   `Hello|`.
2. Start dictation and say `HelloEn`.

Assert: the document reads `Hello·Hello.` — one space, not two.
Assert: the space is inserted before the transcription rather than typed into
the document separately.
Assert: the existing text is otherwise untouched.

## Adds nothing when whitespace is already there

1. In TextEdit, type `Hello ` with one trailing space and leave the caret
   after it.
2. Start dictation and say `HelloEn`.
3. Repeat with the caret after a tab, at the start of an empty second line,
   and after a blank line.

Assert: no insertion adds a space of its own.
Assert: the whitespace already there is left as it was — one space stays one
space, the tab stays a tab, a line break is not turned into a space.
Assert: the transcription starts at the caret in each case.

## Adds nothing at the start of an empty field

1. Focus an empty TextEdit document.
2. Start dictation and say `SentenceEn`.

Assert: the document begins with the transcription, with no leading space.
Assert: the same holds for the first insertion into an empty browser text
field and an empty Notes note.

## Adds nothing after something that opens

1. In TextEdit, type `He said (` and leave the caret after the bracket.
2. Start dictation and say `HelloEn`.
3. Repeat with the caret after `"`, after `[`, and after `{`.

Assert: no space is added in any of the four cases.
Assert: a hyphen is not treated this way: with the caret after `co-`, a space
is added, because a hyphen ends a word as often as it joins one and nothing in
the field says which.
Assert: an em dash is treated as an ordinary character too, and takes a space.

## Spaces both sides of a mid-sentence insertion

1. In TextEdit, type `The fox jumps over the dog.` and place the caret between
   `over` and `the`, directly after the space: `over |the dog.`.
2. Start dictation and say `HelloEn`.

Assert: no space is added before the insertion — one is already there.
Assert: a space is added after it, so the text that follows is not run
together with what was inserted.
Assert: placing the caret with no space on either side — `over|the` — gets a
space on both sides.
Assert: the text after the caret is not moved onto a new line or otherwise
reflowed.

## Adds nothing before punctuation that attaches

1. In TextEdit, type `The fox jumps.` and place the caret directly before the
   full stop: `jumps|.`.
2. Start dictation and say `HelloEn`.

Assert: a space is added before the insertion.
Assert: no space is added after it — the full stop stays attached to the
inserted text rather than being pushed off it.
Assert: the same holds before `,` `;` `:` `!` `?`, before a closing `)` `]`
`}`, and before a closing quote.

## Adds nothing before whitespace or the end of the field

1. In TextEdit, type `Hello  world` with the caret in the double space between
   the words.
2. Start dictation and say `HelloEn`.
3. Repeat with the caret at the very end of the document, and at the end of a
   line that has further lines below it.

Assert: no trailing space is added in any of the three cases.
Assert: the insertion at the end of a line does not consume the line break or
pull the next line up.

## Inserts inside a word

1. In TextEdit, type `Hello` and place the caret between the `l` and the `o`:
   `Hell|o`.
2. Start dictation and say `HelloEn`.

Assert: a space is added on both sides, by the same rule as any other pair of
letters.
Assert: nothing tries to keep the word whole — the rule reads the characters
around the caret, not the words.

## Replaces a selection

1. In TextEdit, type `The fox jumps over the dog.` and select the word `fox`.
2. Start dictation and say `HelloEn`.

Assert: the selection is replaced by the transcription.
Assert: spacing is decided from the characters outside the selection, not from
the selected text: `The` and `jumps` already have their spaces, so none is
added.
Assert: selecting `fox ` with its trailing space gets a space after the
insertion, because what now follows the caret is a letter.
Assert: selecting to the end of the document gets no trailing space.

## Follows the caret rather than the last insertion

1. Start dictation with an empty TextEdit document focused.
2. Say `HelloEn` and wait for the insertion.
3. Type `,` directly after the inserted text, with no space.
4. Say `SentenceEn`.

Assert: a space is added after the comma that was typed, because that is what
the field says — not withheld on the grounds that Overhear inserted the text
before it.
Assert: moving the caret to the start of the document between utterances gets
no leading space and a trailing one.
Assert: switching to another application between utterances spaces against
that application's field.

## Several utterances in a row

1. Start dictation with an empty TextEdit document focused.
2. Say `HelloEn`, pause two seconds.
3. Say `SentenceEn`, pause two seconds.
4. Say `HelloEn`, pause two seconds.

Assert: the three insertions are separated by exactly one space each.
Assert: the first is not given a leading space.
Assert: no space is left dangling at the end of the document.
Assert: the sentences themselves are unchanged — spacing adds nothing inside a
transcription and removes nothing from it.

## An utterance that filters away leaves no space behind

1. Confirm **Strip transcription annotations** is on.
2. In TextEdit, type `Hello` and leave the caret after it.
3. Start dictation and say `Coughing`.

Assert: nothing at all is inserted — not a lone space.
Assert: the document still reads `Hello`.
Assert: dictation stays active.

Spacing runs on what is about to be inserted. With nothing to insert there is
nothing to space, and the setting must not turn a dropped annotation into a
visible edit.

## Text that arrives with its own spacing

1. In TextEdit, type `Hello` and leave the caret after it.
2. Start dictation and say an utterance the model transcribes with a leading
   space or leading punctuation — a continuation after a pause is the usual
   way to get one.

Assert: the insertion has one space before it, whether the space came from the
transcription or from Overhear.
Assert: a transcription that begins with `.` `,` or another attaching mark is
inserted with no space before it.
Assert: a transcription that ends with a space is not given a second one when
the caret is mid-sentence.

## Chinese next to Chinese

1. Select Chinese — `Specs/Languages.md`.
2. In TextEdit, type `你好` and leave the caret after it.
3. Start dictation and say `SentenceZh`.

Assert: no space is added between the two.
Assert: the same holds for Japanese and Thai.
Assert: a Chinese transcription inserted after English text does take a space,
and so does English inserted after Chinese — the rule is about the two
characters meeting at the caret, not about the language of the utterance.

## Pasting a recent transcription

1. Dictate two utterances so both are listed under **Last Transcriptions**.
2. In TextEdit, type `Hello` and leave the caret after it.
3. Open the menu bar menu and click the second entry.

Assert: the entry is inserted with a space before it, by the same rule as a
live transcription.
Assert: the entry in the menu is unchanged — the space is added on the way
into the document, not stored with the transcription.
Assert: **Last Transcriptions** shows every entry as transcribed, with no
leading or trailing space of Overhear's making.

## An application that does not expose its text

1. Start dictation and focus Terminal at a prompt with a partly typed command.
2. Say `HelloEn`.

Assert: the transcription is inserted.
Assert: nothing is added on either side, rather than a space guessed at.
Assert: no error is shown and dictation stays active.
Assert: the same holds in any other field whose contents Overhear cannot read,
including a password field and a canvas-drawn editor in a browser.

## An Electron application

1. Start dictation and focus the message box in Slack, or another Electron
   application, with a word already typed and the caret after it.
2. Say `HelloEn` and wait for the insertion.
3. Say `HelloEn` again.

Assert: the second insertion is spaced.
Assert: the first is spaced too, or inserted unspaced — Chromium builds the
accessibility tree only once it is asked to, and the asking and the reading
happen in the same breath.
Assert: nothing is asked of the user, and no permission dialog appears.
Assert: the application is asked once — a third and fourth utterance are
spaced like the second.
Assert: quitting and reopening the application starts the same way: at worst
one unspaced insertion, then spacing.

## One paste, one undo

1. In TextEdit, type `Hello` and leave the caret after it.
2. Start dictation, say `HelloEn`, and wait for the insertion.
3. Press Cmd+Z once.

Assert: the transcription and the space added with it disappear together.
Assert: the document is back to `Hello`, with no space left behind.
Assert: one more Cmd+Z undoes what was typed in step 1, not a second part of
the insertion.
Assert: the clipboard is restored as it always is, and carries no trace of the
spacing — `Specs/TranscriptionOutput.md`.

## Off inserts exactly what was transcribed

1. Open **Settings… → General** and turn **Ensure spaces around inserted text**
   off.
2. In TextEdit, type `Hello` and leave the caret after it.
3. Start dictation and say `HelloEn`.

Assert: the document reads `HelloHello.` — nothing is added.
Assert: an insertion mid-sentence is run together with the text on both sides.
Assert: nothing is removed either: whitespace the transcription arrives with
still goes in.

## Turning it on takes effect on the next utterance

1. With the setting off, dictate an utterance and see it arrive unspaced.
2. Open **Settings… → General** and turn **Ensure spaces around inserted text**
   on, leaving dictation running.
3. Say `HelloEn` again.

Assert: the second insertion is spaced.
Assert: no engine reload happens and dictation is not interrupted.
Assert: the insertion already in the document is not retrospectively changed.
Assert: turning it off again takes effect on the next utterance the same way.
