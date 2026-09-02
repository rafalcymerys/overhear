# Transcription Model

Choosing which model transcribes speech. The **Transcription** pane states the
active model at the top, offers its language selection beneath it, and lists
every model Overhear can run below that, grouped by the engine that runs it.
Each model can be downloaded, activated and removed.

> Terminology: "engine" here means a transcription backend — Whisper or
> Parakeet — and is the name of a group in the model list. The dictation
> engine that the rest of the specs restart and reload is a different thing;
> this file says "the model reloads" for that.

## Opens the Transcription pane

1. Click the menu bar icon and choose **Settings…**.
2. Click **Transcription**.

Assert: the toolbar has three items: General, Transcription and Hot Words.
Assert: **Transcription** sits second, between General and Hot Words.
Assert: there is no Languages item — language selection lives in this pane.
Assert: the window title changes to "Transcription".
Assert: the window resizes to fit the pane and stays anchored at its top-left
corner.

## States the active model at the top

1. Open **Settings… → Transcription**.

Assert: the pane opens with an **Active Model** section above everything else.
Assert: the section names the model as the user knows it, such as "Whisper
Base", not a repository or variant identifier such as
`openai_whisper-base`.
Assert: it states how much space the model takes on disk and that it runs on
the Neural Engine.
Assert: it does not repeat the language count, which the **Languages** row
below it carries.
Assert: it shows a status indicator reading **Ready** once the model is loaded.
Assert: the indicator reads **Loading…** while the model loads, and says so
when loading failed rather than showing **Ready**.

## Offers the model's languages in the same card

1. Open **Settings… → Transcription**.

Assert: a **Languages** row sits directly under the active model, inside the
same card.
Assert: the row's control summarises the selection, such as "English, Polish".
Assert: an explanation states how many languages the active model recognises.
Assert: the languages a model supports are a property of the model shown above
them, not a separate pane.

The selection itself — the pull-down, its search, and what happens to a
language the active model cannot transcribe — is `Specs/Languages.md`.

## Lists models grouped by engine

1. Open **Settings… → Transcription**.

Assert: an **Available Models** section sits below the active model.
Assert: its models are grouped under two headings, **Whisper** and **Parakeet**.
Assert: the **Whisper** group lists Tiny, Base, Small and Large v3 Turbo.
Assert: the **Parakeet** group lists Parakeet TDT 0.6B v2 and Parakeet TDT 0.6B
v3, at about 450 MB and 470 MB.
Assert: each group heading says in a few words what the engine is, such as
"multilingual" or "fastest".
Assert: on a Mac without Apple silicon the Parakeet group is absent entirely,
rather than offering models that cannot load.
Assert: every model row shows its name, its download size and, where it
differs from the group, the languages it supports.
Assert: no row carries a raw repository or variant identifier.

## Collapses an engine group

1. Open **Settings… → Transcription**.
2. Click the disclosure triangle next to **Parakeet**.

Assert: the group's models are hidden and the heading stays visible.
Assert: the pane shortens and the window resizes to fit.
Assert: the group that holds the active model cannot be left hiding it —
either it stays expanded, or the heading says the active model is inside.
Assert: the collapsed state is remembered the next time the pane is opened.

## Model states on a fresh install

1. Remove `~/Library/Application Support/Overhear/`.
2. Complete first launch.
3. Open **Settings… → Transcription**.

Assert: the **Active Model** section names Whisper Base.
Assert: Whisper Base is the only model marked active in **Available Models**.
Assert: the active row is marked with a label reading **Active**, not only a
highlight.
Assert: every other model offers a download control and nothing else.
Assert: no model other than Whisper Base has been downloaded.

## Downloads a model

1. Open **Settings… → Transcription**.
2. Click the download control on Whisper Small.

Assert: the control is replaced by a progress indicator in the same row.
Assert: the row states how much of the download has arrived.
Assert: the rest of the list stays usable while the download runs.
Assert: dictation keeps working with the active model throughout.
Assert: the row offers **Activate** and a remove control when the download
completes.
Assert: the model is not activated by the download.
Assert: the **Active Model** section is unchanged by the download.

## Downloads two models at once

1. Open **Settings… → Transcription**.
2. Click download on Whisper Small.
3. Without waiting, click download on Parakeet TDT 0.6B v2.

Assert: both rows show their own progress.
Assert: neither download restarts or cancels the other.
Assert: both end up downloaded.

## Cancels a download in progress

1. Start downloading Whisper Large v3 Turbo.
2. Click the cancel control next to its progress indicator.

Assert: the download stops.
Assert: the row goes back to offering the download control.
Assert: no partial files are left in the model's directory.
Assert: the model can be downloaded again afterwards.

## Recovers from a failed download

1. Disconnect from the network.
2. Open **Settings… → Transcription** and start downloading Whisper Small.
3. Wait for the download to fail.
4. Reconnect and click **Try Again**.

Assert: the row states that the download failed and why.
Assert: the row offers **Try Again**.
Assert: no partial files are left behind.
Assert: **Try Again** completes the download.
Assert: the active model is unaffected by the failure.

## Activates a downloaded model

1. Download Whisper Small.
2. Click **Activate** on it.

Assert: the **Active Model** section changes to Whisper Small, along with its
size on disk and its language count.
Assert: the **Active** label moves to Whisper Small in the list.
Assert: Whisper Base stays downloaded and now offers **Activate**.
Assert: the model reloads once.
Assert: the status indicator returns to **Ready** when the reload finishes.
Assert: the menu bar icon shows the loading state while it reloads.

## Activation is offered only for downloaded models

1. Open **Settings… → Transcription** with Whisper Base the only downloaded
   model.

Assert: no row that has not been downloaded offers **Activate** or a remove
control.
Assert: the active row offers neither **Activate** nor a download control.

## Transcribes with the activated model

1. Activate Whisper Small and wait for the reload to finish.
2. Start dictation with TextEdit focused.
3. Say `SentenceEn`, pause, then say `SentencePl`.

Assert: both utterances are inserted.
Assert: each is inserted in the language it was spoken in.
Assert: the transcriptions come from Whisper Small — nothing falls back to
Whisper Base.

## Switching engines

1. Download Parakeet TDT 0.6B v3 and activate it.
2. Start dictation with TextEdit focused.
3. Say `SentenceEn`.

Assert: the **Active Model** section names the Parakeet model and its engine.
Assert: the utterance is inserted.
Assert: the Whisper models stay downloaded and are still listed.
Assert: switching back to a Whisper model is one click on **Activate** and does
not download anything again.
Assert: **Translate unsupported languages** is gone from the General pane while
the Parakeet model is active, and returns when a Whisper model is.
Assert: punctuation, capitalisation and how numbers are written may differ
between the engines. The same sentence dictated under each is not expected to
come back identical.

## Speech outside the selected languages under Parakeet

1. Select English only and activate Parakeet TDT 0.6B v3.
2. Start dictation with TextEdit focused.
3. Say `SentencePl`.

Assert: nothing is inserted.
Assert: no entry appears under **Last Transcriptions**.
Assert: dictation carries on, ready for the next utterance.

Whisper is told which language to decode, so its output stays inside the
selection by construction. Parakeet cannot be told — the selection is a hint
that steers it — so a transcription that comes back in a language the user did
not select is discarded rather than pasted. A few words are kept regardless:
too short a sample cannot be judged, and dropping what someone said on a guess
is worse than the occasional stray line.

## Activating an English-only model narrows the languages

1. Select English and Polish in the **Languages** row.
2. Download Parakeet TDT 0.6B v2, which supports English only, and activate it.

Assert: the **Active Model** section states that this model recognises English
only.
Assert: the **Languages** row summarises the selection as English alone.
Assert: the user is told that Polish was dropped because this model cannot
transcribe it.
Assert: activating a multilingual model again restores English and Polish
without the user reselecting them.

## Removes a downloaded model

1. Download Whisper Small and leave Whisper Base active.
2. Click the remove control on Whisper Small.
3. Confirm the removal.

Assert: removal asks for confirmation and names the model and the space it
frees.
Assert: the row goes back to offering the download control.
Assert: the model's files are gone from
`~/Library/Application Support/Overhear/`.
Assert: the active model is untouched and dictation still works.

## The active model cannot be removed

1. Open **Settings… → Transcription**.

Assert: the active model's row offers no remove control.
Assert: at least one model is downloaded and active at all times.

## Reports how much space the models take

1. Open **Settings… → Transcription** with two models downloaded.
2. Download a third and wait for it to finish.
3. Remove one.

Assert: the pane states the total space the downloaded models take.
Assert: the total counts every downloaded model, including the active one.
Assert: it grows when a download completes and shrinks when a model is removed,
without reopening the window.

## Activating while dictating

1. Start dictation and confirm the active state in the menu bar.
2. Speak an utterance and, before it is inserted, open
   **Settings… → Transcription** and activate another downloaded model.

Assert: the audio dictated so far is discarded — the batch being recorded and
any batch mid-transcription are both dropped.
Assert: nothing from that audio is inserted, then or after the reload.
Assert: no discarded batch appears under **Last Transcriptions**.
Assert: the model reloads.
Assert: dictation is active again after the reload, or the user is told it
stopped.
Assert: text inserted before the activation is left alone.

## Downloading while dictating

1. Start dictation.
2. Open **Settings… → Transcription** and download a model.
3. Speak an utterance while the download runs.

Assert: the utterance is transcribed by the active model as usual.
Assert: the download does not reload the model or interrupt dictation.

## The choice survives a restart

1. Download and activate Whisper Small.
2. Quit Overhear and open it again.
3. Open **Settings… → Transcription**.

Assert: the **Active Model** section still names Whisper Small.
Assert: nothing is re-downloaded.
Assert: the models downloaded before quitting are still listed as downloaded.

## Re-downloads the active model when its files are gone

1. Quit Overhear with Whisper Small active.
2. Delete Whisper Small's files from
   `~/Library/Application Support/Overhear/`.
3. Open Overhear.
4. Open **Settings… → Transcription**.

Assert: Whisper Small is downloaded again on launch, without being asked for.
Assert: the user is told the model is being fetched again and sees its progress.
Assert: Whisper Small stays the active model throughout — Overhear does not
fall back to another model or to Whisper Base.
Assert: dictation becomes available once the download finishes, and not before.
Assert: models other than the active one are not re-downloaded when their files
are gone.
Assert: a re-download that fails is reported with **Try Again**, the way the
first-launch download is.
