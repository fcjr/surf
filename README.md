# Surf

Use an Apple TV remote with your Mac.

Surf is a menu bar app for the Mac plugged into your TV. Swipe the remote to move
the pointer, click to select something, or hold Siri to dictate into a text field.
You can leave the keyboard on the coffee table.

## Try it

There isn't a packaged release yet. For now, see the [build instructions](docs/development.md).
Development builds use ad hoc signing; no Apple developer account is needed.

The project targets macOS 14 Sonoma and later. The remote code was developed with
the third-generation USB-C Siri Remote. Other remote models still need testing.

## Pair your remote

The remote can only be paired with one host at a time. Pairing it with your Mac
takes it away from your Apple TV.

1. Put the Apple TV to sleep so it doesn't keep grabbing the remote back.
2. Hold **Back + Volume Up** for five seconds. The remote should appear under
   **Nearby** in Surf's menu.
3. Click **Pair**, then **Connect**. If it times out, hold the buttons again and retry.

Once paired, Surf shows the remote's connection status and battery level.

To switch back to the Apple TV, click **Forget…** in Surf. This opens Bluetooth
settings, where you can remove the remote. Then hold it near the Apple TV and press
Back + Volume Up again.

## Use it as a mouse

Enable **Touch surface moves the pointer** in Surf's menu. You'll need to allow
Surf in System Settings → Privacy & Security → Accessibility.

- Swipe with one finger to move the pointer. Slow movements give you finer control.
- Swipe with two fingers to scroll. Lift your fingers to let it coast; touch again
  to stop.
- Press the center to click. Keep it pressed while moving to drag.

Adjust the **Speed** slider if the pointer feels too slow or too twitchy.

## Buttons

These are the defaults:

| Button | Action |
| --- | --- |
| Clickpad ring | Arrow keys, repeating while held |
| Clickpad center | Click, when mouse control is enabled |
| Back | Escape |
| TV | Mission Control |
| Power | Put the displays to sleep |
| Siri | Dictate while held, when dictation is enabled |
| Play/Pause, Mute, Volume | Standard media controls |

Pressing the ring sends an arrow key rather than a mouse click. If you're already
dragging, moving onto the ring keeps the drag going.

Click **Customize…** to change a button. The picture of the remote lights up as you
press the real buttons. You can assign a key or a recorded shortcut, choose an
action like Mission Control, or make a button do nothing. **Reset to defaults**
puts it all back.

## Dictation

Enable **Hold Siri to dictate**, then hold the Siri button and speak. Text appears
in the focused field as you talk and finishes when you release the button. The
first time you enable it, Surf downloads a speech model. Wait for that to finish
before trying it.

One catch: Surf uses your Mac's microphone, not the one in the remote. A display,
webcam, or external mic also works if it's your Mac's default input.

Dictation currently recognizes English. Speech recognition runs locally through FluidAudio. Surf downloads the model and
checks GitHub for app updates, but it doesn't upload your audio for transcription.

Dictation needs Microphone and Accessibility access. Without Accessibility access,
the transcript goes to the clipboard instead. Surf also uses the clipboard when
macOS secure input is active.

## Permissions

| Permission | Why Surf needs it |
| --- | --- |
| Bluetooth | Find and pair the remote |
| Accessibility | Move the pointer, send clicks and keystrokes, and remap media buttons |
| Microphone | Listen while you dictate |

## Troubleshooting

- **Nothing under Nearby?** Hold Back + Volume Up for the full five seconds and
  make sure the Apple TV is asleep. If the remote appeared and disappeared, try again.
- **The remote still remembers another host?** Sleep the Apple TV, put the remote
  back in pairing mode, and retry.
- **Paired, but no touch surface?** Press a button to wake the remote and give it a
  moment to connect. Touch input can take a little longer than the buttons.
- **No pointer movement or typed text?** Check Surf's Accessibility permission.
  After rebuilding or replacing the app, you may need to remove its old entry and
  add it again.

Touch input uses Apple's private MultitouchSupport framework. It may need fixes
after macOS updates.

## Development

See [docs/development.md](docs/development.md) for build commands and the release process.

## License

MIT, copyright 2026 Left Shift Logical, LLC. See [LICENSE](LICENSE).
Adapted code and dependencies retain their own licenses; their notices are in
[Surf/Resources/Licenses](Surf/Resources/Licenses) and included in the app.
