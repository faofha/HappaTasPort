# Chat replay (HappaTAS 3, V3.1) - short design

## Intent

Anything typed into Roblox's chat while recording in Create is part of the TAS. Example: typing "/e dance2" makes
the character dance. When the TAS plays in Test, it types the same thing into the chat bar again, letter by letter
on the same frames, and sends it on the frame it was sent. The character dances again, and anyone watching sees
the TAS typing.

## Goals

- Replay looks like the player typing: the chat bar opens, the text grows at the recorded speed, then it is sent
  (or closed without sending, if that is what happened).
- Commands ("/e dance2", "/e cheer") and normal messages behave as they did while recording, because they go
  through Roblox's own chat bar.
- Old `.tas` files load unchanged; the file format version stays 6.

## Non-goals

- The legacy chat (old games with `Chat` / `Player.Chatted` only): chat bar of TextChatService only.
- Messages from other players, whispers' replies, the chat window's scroll position.
- Typing while paused or scrubbing (only recording records, only Test replays).

## Anti-goals

- Never press real keys for it (keypress): layouts and window focus would break it.
- HappaTAS's own keys and the recorded game inputs must not react to the replayed typing.

## Approaches

- **A. Record the chat bar itself (picked by dzr).** The chat bar's text is saved on every frame it changes, plus
  open / send / close; Test sets the same text on the same frames and sends it with the chat bar's own submit.
- B. Save only the sent text and its frame, type it out quickly before that frame. Less data, typing doesn't match.
- C. Replay through keypress like Replay Keyboard. Rejected: window focus, keyboard layouts, symbols.

## How (decided)

- Checked live (EToH kit test place, TextChatService): the chat bar is
  `CoreGui.ExperienceChat....ChatInputBarV2....TextBox`. From a script, `CaptureFocus()`, setting `Text` letter by
  letter and `ReleaseFocus(true)` sent "/e dance2" and the dance2 animation played, with the Roblox window not
  focused.
- New timeline column `Chat` (list, kept only on frames where something changed): `{ text }` when the bar's text
  changed (the bar is open), `{ text, 1 }` sent, `{ text, 2 }` closed without sending. Saved in v6 files by name.
- Recording: watch the chat bar's TextBox (Focused, Text changed, FocusLost with enterPressed) and write the change
  onto the frame being recorded.
- Test: on each frame with a `Chat` entry: open the bar (CaptureFocus) if needed, set the text, and on "sent"
  `ReleaseFocus(true)` (Roblox sends it), on "closed" `ReleaseFocus(false)`.
- Setting **Replay Chat** (Inputs, on): off = Test skips the chat column.
- Normal messages are really sent on every Test (other players see them again; Roblox filters and rate limits).
  Help says so.

## Builder's calls (Claude's, can be changed)

- Test started mid-typing (Restart When Testing off): starts with the bar holding the text of the last change
  before that frame.
- Test stopped, paused or ended while the bar is open: the bar is closed without sending and emptied.
- Playback Speed other than 1: entries play on their frames, so typing speeds up / slows down with it.
- Frames recorded over (unpause earlier) drop their chat entries like every other column.
- No chat bar found (legacy chat, or the game hides it): nothing is recorded; Test skips chat. Help mentions it.
- Typing replay never counts as player typing for HappaTAS's keys guard in a way that blocks Test's own controls;
  the Test quit control keeps working.
- Help: a paragraph in "Keyboard and Mouse Inputs"; update log line under V3.1.
