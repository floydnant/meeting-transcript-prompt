# Meeting Transcript Prompt

A small macOS menu bar app that reminds you to open your preferred transcription app when a meeting starts.

It combines two independent signals:

- Eligible events from calendars already configured on the Mac
- Per-process microphone activity from Microsoft Teams, combined with recent Teams focus

The detector does not listen to or store audio. The transcription app is selected locally in Settings and identified by its bundle identifier.

## Requirements

- macOS 14.2 or newer for per-process microphone detection
- Xcode 16 or newer
- A desktop transcription app installed on the Mac

## Build and test

```sh
make test
make app
```

The packaged app is written to `dist/Meeting Transcript Prompt.app`. The packaging script uses an ad hoc signature for local development.

After signing the rebuilt app, the packaging script resets its macOS Accessibility permission with the bundle identifier read from the packaged `Info.plist`. macOS will ask for permission again when you test recording automation.

Open `Package.swift` in Xcode to develop and debug the project.

## First run

1. Build the app with `make app`.
2. Move it to `/Applications` if you want Launch at Login to work reliably.
3. Open Settings from the menu bar panel.
4. Choose the desktop transcription app to open.
5. Grant Calendar access and select the calendars to monitor.
6. Add dictation apps under Rules so they can suppress Teams prompts while active.
7. Keep experimental recording auto-start off until you have tested the normal prompt flow.

Experimental auto-start requires Accessibility permission. It searches the selected app's accessibility tree for a recording button and never clicks fixed screen coordinates.

The General settings tab has two development controls:

- `Show test meeting prompt` runs the complete prompt flow without a calendar event or Teams call.
- `Check Record button` opens the selected app and verifies that the Record control is accessible without pressing it.

`Show test meeting prompt` is also available directly from the menu bar panel.

## Privacy

Diagnostics stay in `~/Library/Application Support/MeetingTranscriptPrompt/diagnostics.jsonl` and expire after seven days. Logs contain timestamps, application bundle identifiers, trigger decisions, and opaque event identifiers. They do not contain audio, attendee names, event titles, or transcripts.
