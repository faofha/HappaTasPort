# Chat Replay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** What is typed into Roblox's chat bar while recording in Create is saved per frame and typed + sent again through the same chat bar in Test.

**Architecture:** A new world plugin `world/chat` (order 56, after thumbstick) owns the column `Chat`, watches the
chat bar TextBox (CoreGui.ExperienceChat, found by name) while recording, and replays the entries in Test with
CaptureFocus / Text / ReleaseFocus(submitted). `platform/typing` learns that a replay-owned chat bar is not the
player typing. Setting `replayChat`.

**Tech Stack:** Luau (conservative syntax), headless mock `tests/mock`, `tests3/test_chat.lua`.

**Spec:** `docs/superpowers/specs/2026-11-22-chat-replay-design.md`

## Global Constraints

- File format version stays 6; the column is matched by name (`Chat`, list, width 1); old files load (no `Chat`).
- No keypress for chat; only the chat bar's TextBox (CaptureFocus, Text, ReleaseFocus(true) = send, ReleaseFocus(false) = close).
- Conservative Luau: no `+=`, `//`, backtick strings, `continue`, if-expressions; mind the 200-locals limit.
- No network code; never quote dzr's requests in commits / PRs; commits with `git -c user.name=Claude -c user.email=noreply@anthropic.com` ending `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; never commit wow1.
- Every task ends with `bash tools/test_all3.sh` green (traces SAME, bench OK).

## Review Focus

1. Playback Speed > 1 (or a long frame) skips frames in `onPlayTo`: a "sent" entry on a skipped frame must still be sent, in order (Task 2 test "skipped frames").
2. Recording over: unpausing earlier cuts later frames; their Chat entries go with them (Task 1 test "cut").
3. Test stops / pauses / ends with the bar open: closed WITHOUT sending, text emptied (Task 2 test "stop mid-typing").
4. A run saved with chat and loaded again replays the same; a file without `Chat` loads and replays nothing (Task 2 test "save / load").
5. No chat bar (legacy chat or hidden): no errors, nothing recorded, Test skips (Task 1 test "no chat bar").

---

### Task 1: Recording the chat bar

**Files:**
- Create: `src2/world/chat.lua`
- Modify: `src2/modules.txt` (after `world/thumbstick`), `src2/main.lua` (`E.chat = guard(E.plugins:add(Chat.new(E)), "chat")` after thumbstick)
- Modify: `tests/mock/svc.lua` (chat bar model)
- Test: `tests3/test_chat.lua` (`-- needs:` none beyond the default)

**Interfaces:**
- Produces: column `Chat` (list): per frame an array of entries `{ text }` (text changed / bar opened), `{ text, 1 }` (sent), `{ text, 2 }` (closed without sending); frames with no change hold nil.
- Produces: `Chat:box() -> TextBox?` (the chat bar's TextBox: `CoreGui.ExperienceChat`, then the first TextBox
  under a descendant named `ChatInputBarV2`; looked up again at most every 2 s while missing or unparented).
- Produces: `Chat:fill(tl, i)` writes the changes seen since the last fill onto frame i (only while recording:
  `E.mode == 2 and not E.paused`); changes while not recording are dropped. If recording starts with the bar
  already open, the first fill writes `{ box.Text }`.
- Mock produces: `M.chatBox` (TextBox at `CoreGui.ExperienceChat.appLayout.chatInputRow.fillArea.chatInputBar.ChatInputBarV2.Container.InputGroup.TextContainer.TextBoxContainer.TextBox`),
  `M.chatSent` (texts Roblox "sent"), `M.noChatBar` (set before boot: no ExperienceChat).
  `ReleaseFocus(submitted)` fires `FocusLost(submitted == true)`; for `M.chatBox`, a submitted non-empty text is
  appended to `M.chatSent` and `Text` becomes "" (after FocusLost, like Roblox). `M.chatBar.IsFocused` follows
  `M.chatBox` focus.

- [ ] **Step 1: Mock chat bar.** Add the model above to `tests/mock/svc.lua` (`M.focus(box, submitted)` passes `submitted` to the old box's FocusLost).
- [ ] **Step 2: Write the failing test** `tests3/test_chat.lua`, sections:
  - "recording": Create, unpause; `M.chatBox:CaptureFocus()`, set Text "/", "/e", "/e dance2" on three different frames (M.step between), `M.chatBox:ReleaseFocus(true)`. Expect the frames' `Chat` entries in order: `{ "" }` or `{ "/" }` on the open frame, then `{ "/e" }`, `{ "/e dance2" }`, and `{ "/e dance2", 1 }` on the send frame; `M.chatSent[1] == "/e dance2"`.
  - "closed without sending": open, type "hi", `ReleaseFocus(false)` -> last entry `{ "hi", 2 }`.
  - "paused: nothing recorded": pause, type into the bar -> no new entries.
  - "cut": record chat on frames 20-25, go back to frame 10, unpause, record 3 frames -> frames > 13 hold no Chat entries.
  - "no chat bar": a second boot with `M.noChatBar = true`, record with typing calls guarded -> boots, records, no error reported (`E.errs` / reportError count unchanged).
- [ ] **Step 3: Run** `bash <scratchpad>/suites.sh chat` - Expected: FAIL (no `Chat` column).
- [ ] **Step 4: Implement `world/chat.lua`** (plugin `{ name = "chat", order = 56 }`, `Chat.new(E)` adds the column with `E.tl:addColumn("Chat", "list", 1, { key = "Chat", keep = true })`; connections Focused / FocusLost / `GetPropertyChangedSignal("Text")` made once per found box, in `E` life scope). Pending changes: a queue; consecutive text changes in one frame collapse to the last; open / send / close are never collapsed.
- [ ] **Step 5: Run** chat + `inputs typing modes persist` suites - Expected: PASS.
- [ ] **Step 6: Gate + commit** `HappaTAS 3: chat typed while recording is saved per frame`.

### Task 2: Replaying the chat in Test

**Files:**
- Modify: `src2/world/chat.lua`, `src2/platform/typing.lua`, `src2/engine/settings.lua`
- Test: `tests3/test_chat.lua` (more sections)

**Interfaces:**
- Consumes: Task 1's column and `Chat:box()`.
- Produces: `Chat:onPlaybackBegin(tl, f)`: `self.played = f - 1`; if the last entry at or before f - 1 leaves the bar open (its kind is nil), open the bar with that text.
- Produces: `Chat:onPlayTo(tl, f)`: when `replayChat` is on, applies every entry of frames `played + 1 .. f` in order (`f < played`: close the bar without sending, then like onPlaybackBegin at f + 1), then `played = f`.
- Produces: `Chat:onEndPlayback()` and `Chat:onPause()` while it owns the bar: `Text = ""`, `ReleaseFocus(false)`, owns = false.
- Produces: `E.typing.chatReplay` (boolean): true while Chat owns the bar; `Typing:active()` then ignores the chat bar's focus (HappaTAS's Test controls keep working).
- Produces: setting `row("replayChat", "Replay Chat", "Inputs", 1, { desc = "Types the recorded chat into the chat bar again while testing" })` after `replayMouseMovement`.

- [ ] **Step 1: Write the failing tests** (sections in `test_chat.lua`):
  - "Test types and sends": record "/e dance2" (Task 1 way), Test from frame 1 -> on the recorded frames `M.chatBox.Text` equals each recorded text, `M.chatSent` gains "/e dance2" exactly once, on the send frame.
  - "skipped frames": playbackSpeed 3 -> still sent once, after the texts.
  - "start mid-typing": restartWhenTesting off, Test from a frame between the open and the send -> the bar opens at once with the text recorded before it, then sends.
  - "stop mid-typing": Test, press Idle on a frame between open and send -> `M.chatSent` unchanged, `M.chatBox.Text == ""`, not focused.
  - "keys still work": while the replay owns the bar, `E.typing:active()` is false.
  - "Replay Chat off": nothing typed or sent.
  - "save / load": save, clear, load, Test -> sent again; a file saved before (a timeline without the column written) loads and Test sends nothing.
- [ ] **Step 2: Run** - Expected: FAIL.
- [ ] **Step 3: Implement** the hooks above; setting row; typing flag.
- [ ] **Step 4: Run** chat, typing, settings, settingswin, tsettings, classicrows - Expected: PASS (fix setting counts tests only if they pin the Inputs row list, with a comment).
- [ ] **Step 5: Gate + commit** `HappaTAS 3: Test types the recorded chat again`.

### Task 3: Help, update log, live check

**Files:**
- Modify: `src2/ui/win/helptext.lua` (a "Chat:" paragraph in topic `inputs`, V2 style: recorded per frame, typed and sent again in Test through the chat bar, commands like /e dance2 work, normal messages are really sent again so others see them, Replay Chat turns it off, only Roblox's current chat), `src2/ui/updatelog.lua` (a V3.1 bullet).
- Test: `tests3/test_chat.lua` section "help": topic `inputs` body contains "Replay Chat".

- [ ] **Step 1: failing help check, then the text; run help, pages, updatelog, chat - PASS.**
- [ ] **Step 2: Gate.**
- [ ] **Step 3: Live (EToH kit test place; back up HappaTasPort first, restore byte-identical, delete HappaTasTest):** record typing "/e dance2" in Create, Test: the bar shows the text growing on the recorded frames, the dance2 track plays; a closed-without-sending entry closes the bar; Idle mid-typing closes it unsent.
- [ ] **Step 4: Commit** `HappaTAS 3: chat replay in Help and the update log`, push, PR stacked on #54.
