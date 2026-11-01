# HappaTAS 3 Phase 7: Switch-over Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** HappaTAS 3 becomes the script people run: version 3.0.0 in `wow` / `wow1`, a README for it, and the
spec's five success criteria checked and written down; V2.38.17 stays in git history and as the trace reference.

**Architecture:** No engine change. The version and a "What's new" list live in one place (`config` / `ui/win/helptext`)
and show in both interfaces. A new `tools/release3.sh` writes `wow` and `wow1` from `src2/`; V2's `tools/release.sh`
stops writing `wow`. `test_all3.sh` warns when the committed `wow` is not the release build of `src2/`. The last task
is a live check of the release as dzr will run it, with the criteria report in spec 13.

**Tech Stack:** Luau (src2/), bash + python3 tools, headless mock (tests/mock, tests3/), Real MCP for the live check.

**Spec:** docs/superpowers/specs/2026-10-18-happatas3-rewrite-design.md (sections 1, 6.3, 11, 12 item 7, 13)

## Global Constraints

- "Every feature of V2.38.16 stays. Old `.tas` files and `Settings.json` keep working." (spec 1)
- "7. **Switch-over:** HappaTAS 3 becomes `wow` / `wow1`; README; V2.38.16 stays in history." (spec 12)
- Conservative Luau: no `+=`, `//`, backtick strings, `continue`, if-expressions; never name getfenv / setfenv;
  200 locals per function.
- No network code (no HttpGet / request / loadstring).
- Executor docs only from docs.projectreal.gg, docs.potassium.pro, sunc.su.
- Interface text uses only characters every listed font has (ASCII and × ▼ ← … •).
- Never publish dzr's Claude data (CLAUDE.md, claude/, session links); never quote dzr's requests in commits / PRs.
- Commits: `git -c user.name="Claude" -c user.email="noreply@anthropic.com"`, ending with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- `wow` and `wow1` are byte-identical (README "Files": wow1 is the same file).
- dzr's `works` file and V2's `src/`, `tests/` stay as they are (the mock in tests/ is shared; trace3.sh builds V2
  from commit aaa21b6, not from the working tree).
- Live tests: back up Settings.json, Settings3.json and the place's files and restore them byte-identical; record
  getfpscap() and the graphics quality and put them back; use HappaTasTest/ and delete it; never run anything in
  Tower Creator.

## Review Focus

1. Someone runs V2's `bash tools/release.sh` (habit, old notes) after the switch: `wow` must not turn back into V2.
2. A player whose `Settings3.json` came from a dev build while they kept using V2: HappaTAS 3 keeps that file (V2's
   newer `Settings.json` is not converted again); README and Help must say how to convert again.
3. Going back to V2 from git history after saving v6 files: V2 refuses them with "unsupported file version 6"
   and never overwrites them; the README says so.
4. Running the new `wow` while the old V2 `wow` is loaded in the same client: the old copy unloads (main.lua already
   unloads `__HappaTAS`), one interface, one set of keys.
5. `wow` hand-edited or left stale after a src2 change: the gate says so instead of passing silently.

---

### Task 1: Version 3.0.0 and "What's new" in both interfaces

**Files:**
- Modify: `src2/config.lua:5` (VERSION)
- Modify: `src2/ui/win/helptext.lua` (WHATS_NEW list + a "What's new" topic, first after "Getting started")
- Modify: `src2/ui/classic/tree.lua` (MoreFrame.List: a `3UpdateLog` frame built from WHATS_NEW, between
  `4CreditsN` and `0ModelN` in the list's name order, as V2's was; header comment: the update log is back)
- Test: `tests3/test_help.lua`, `tests3/test_classictree.lua`; the version pins in `tests3/test_bundle.lua:5`,
  `test_classictree.lua:55` and `test_main.lua:22` become `"3.0.0"` (the fixtures' `script = "3.0.0-dev"` in
  test_codec6 / test_library / test_librarywin are file header data and stay)

**Interfaces:**
- Produces: `CONFIG.VERSION == "3.0.0"`; `HelpText.WHATS_NEW = { version = "3.0.0", items = { string, ... } }`
  (one line per item, at most 60 characters each so Classic's 12 px rows fit 360 px); topic id `"whatsnew"`, title
  `"What's new"`, body = `"HappaTAS " .. version` then `"• " .. item` per line.
- Classic: `MoreFrame.List.3UpdateLog` = a Frame with `LV("0", " HappaTAS 3.0.0")` and `LI(tostring(i), " " .. item)`
  rows in a UIListLayout, height 30 + 20 * #items.

Items (exact text):
1. `A new interface: Dock, windows, timeline bar, Inspector`
2. `The classic interface is still there (Settings > Interface)`
3. `Library: folders, search, sort, numbered attempts`
4. `File format v6: smaller files, safe saving`
5. `Old .tas files (v1-v5) and Settings.json carry over`
6. `Faster frames, everything undone on Unload`
7. `Touch buttons and thumbstick replay on phones`
8. `The MicroProfiler on the new engine`

- [ ] **Step 1: Write the failing tests**

test_help.lua, new section "what's new (phase 7)":
```lua
eq(__T3("config").VERSION, "3.0.0", "version 3.0.0")
local t = topicById("whatsnew")
check(t ~= nil and t.title == "What's new", "a What's new topic")
eq(order("whatsnew"), order("start") + 1, "right after Getting started")
check(t.body:find("HappaTAS 3.0.0", 1, true) ~= nil, "names the version")
for _, item in ipairs(HelpText.WHATS_NEW.items) do
	check(t.body:find("• " .. item, 1, true) ~= nil, "lists: " .. item)
	check(#item <= 60, "fits a classic row: " .. item)
end
```
(`topicById` / `order` = small local helpers over `HelpText.topics(E)` in the test; `HelpText = __T3("ui/win/helptext")`
as the suite already has.)

test_classictree.lua, new section:
```lua
local log = c.byPath["MainMenu.MoreFrame.List.3UpdateLog"]
check(log ~= nil, "Classic's More tab has an update log again")
eq(c.byPath["MainMenu.MoreFrame.List.3UpdateLog.0"].Text, " HappaTAS 3.0.0", "its version line")
eq(rows("MainMenu.MoreFrame.List.3UpdateLog"), 1 + #HelpText.WHATS_NEW.items, "one row per item (the file's rows() helper)")
```

- [ ] **Step 2: Run them, see them fail**

Run: `bash tools/build_test3.sh help && (cd tests3 && luau run_help.lua)` and the same for `classictree`
Expected: FAIL on "version 3.0.0" / "a What's new topic" / "has an update log again".

- [ ] **Step 3: Implement** the version, `HelpText.WHATS_NEW`, the topic and the classic frame (tree.lua imports
`ui/win/helptext` for the list; add it to modules.txt order only if the import order needs it).

- [ ] **Step 4: Run both suites, then `timeout 3600 bash tools/test_all3.sh`**
Expected: both suites pass; ALL PASSED (traces compare frames, not the version string; if a trace line carries
VERSION, add it to that trace's IGNORE and ledger a ruling).

- [ ] **Step 5: Commit** `HappaTAS 3.0.0: version and What's new in both interfaces`

### Task 2: Release tooling: wow / wow1 from src2

**Files:**
- Create: `tools/release3.sh` (`bash tools/release3.sh` writes `wow`, then copies it to `wow1`)
- Modify: `tools/build3.sh` (the release header: `"HappaTAS <VERSION> - records and replays TAS runs on the client
  (executor script)."`, `"Saves to <executor workspace>/HappaTasPort/<PlaceId>/. Press M for the menu."`,
  `"Release build: comments and blank lines removed. The commented source is src2/ (HappaTasPort repository)."`;
  VERSION read from src2/config.lua)
- Modify: `tools/release.sh` (V2): default OUT becomes `build/wow_v2` (git-ignored `build/`), header comment says
  `wow` is HappaTAS 3 now; `tools/port_release.py` docstring likewise
- Modify: `tools/test_all3.sh` (after building wow3: `cmp -s wow3 wow && cmp -s wow wow1` else print
  `WARNING: wow / wow1 are not the release build of src2 (bash tools/release3.sh)`; a warning, not a failure, so
  work in progress still gates; the main / engine suites keep running on wow3)
- Generated: `wow`, `wow1`

**Interfaces:**
- Consumes: Task 1's `CONFIG.VERSION`.
- Produces: `tools/release3.sh` (no arguments); `wow` == `wow1` == `bash tools/build3.sh --release` output.

- [ ] **Step 1: Write the failing check** `tools/check_release3.sh`: builds a release into a temp file and exits 1
unless `wow` equals it byte for byte, `wow1` equals `wow`, `head -1 wow` is
`-- HappaTAS 3.0.0 - records and replays TAS runs on the client (executor script).`, and running
`bash tools/release.sh` with no argument leaves `wow`'s sha1 unchanged (then deletes `build/wow_v2`).

- [ ] **Step 2: Run it, see it fail** — Run: `bash tools/check_release3.sh` — Expected: exit 1 (`wow` is still V2.38.17).

- [ ] **Step 3: Implement** release3.sh, the header, release.sh's new default, the test_all3 warning; run
`bash tools/release3.sh`.

- [ ] **Step 4: Verify** — `bash tools/check_release3.sh` exit 0; `bash tools/build_test3.sh main wow && (cd tests3 &&
luau run_main.lua)` and the same for `engine` pass on `wow` itself; `timeout 3600 bash tools/test_all3.sh` ALL PASSED
with no WARNING line.

- [ ] **Step 5: Commit** `HappaTAS 3.0.0 is wow / wow1; V2's release.sh no longer writes wow` (wow, wow1, tools).

### Task 3: README and the spec for HappaTAS 3

**Files:**
- Modify: `README.md` (rewritten for HappaTAS 3)
- Modify: `docs/superpowers/specs/2026-10-18-happatas3-rewrite-design.md` 6.3 (what was built: Settings3.json is
  HappaTAS 3's file, V2's Settings.json is read once and never written, so V2 from history keeps its own settings;
  `Settings.v2.json` was not needed) and 12 item 7 (done, with the date)
- Modify: `src2/ui/win/helptext.lua` "start" topic: one sentence on converting V2's settings again

**README sections (in this order):** what HappaTAS 3 is (one paragraph); Quick start (run `wow` in the executor;
Real first, sUNC executors mostly work); Default controls (from `src2/engine/controls.lua`'s defaults, the table
generated by reading the file, not retyped); What it does (the spec 2 "Kept" list in user words); the two interfaces;
Settings and files (`HappaTasPort/Settings3.json`; `<PlaceId>/` runs, folders, attempts, `library.cache`; first
start converts `Settings.json`; to convert again delete `Settings3.json`; v1-v5 files open, a run is rewritten as v6
only when saved again; V2 cannot open v6 files: "unsupported file version 6"); Files in this repository (`wow`,
`wow1` = the same; `src2/`, `tests3/`, `tools/`; `src/`, `tests/` = V2.38.17 kept as the trace reference and the
shared mock; `works`, `true`, `true real`, `nohboard`, `HappaTAS_Executor-2.lua` = older scripts); Building and
testing (`bash tools/release3.sh`, `timeout 3600 bash tools/test_all3.sh`, one suite, traces, bench, savebench);
Version history (3.0.0 = the What's new list, then V2's short history kept from the current README).

- [ ] **Step 1: Write the check** `tools/check_readme3.py`: every `bash tools/...` / `python3 tools/...` command in
README.md names an existing file; the controls table equals the defaults in `src2/engine/controls.lua`; the README
names `Settings3.json`, `unsupported file version 6`, `release3.sh`. Exit 1 on the first miss.
- [ ] **Step 2: Run it** — Expected: exit 1 on the current V2 README.
- [ ] **Step 3: Write README, the spec edits and the Help sentence.**
- [ ] **Step 4: Verify** — `python3 tools/check_readme3.py` exit 0; `bash tools/release3.sh` (the Help text
changed) and `bash tools/check_release3.sh` exit 0; `timeout 3600 bash tools/test_all3.sh` ALL PASSED, no WARNING.
- [ ] **Step 5: Commit** `README for HappaTAS 3; spec 6.3 and 12 as built` (README, spec, helptext, wow, wow1, check script).

### Task 4: Live check of the release and the success criteria report

Only with the Real MCP connected (dzr: "Real is always connected"); EToH kit test place 72164126024589.

**Files:**
- Create: `tools/live/criteria3.lua` (test tool, never shipped): `Crit.playback(scriptPath, tasName, frames)` loads a
  script, loads the named run, Tests it, and returns `{ n, pos = { Vector3 per frame }, len }` sampled as the last
  PreRender handler; unloads; always restores what it changed (pattern: tools/live/meter3.lua)
- Modify: spec 13: a "Phase 7: success criteria" entry, one line per criterion with its evidence
- Modify (local only, never committed): `CLAUDE.md` (`wow` = HappaTAS 3.0.0, phase 7 note)

- [ ] **Step 1: Back up** Settings.json, Settings3.json, every file in the place folder (sha1 + size); record
getfpscap() and the graphics quality.
- [ ] **Step 2: Criterion 5 + load:** `loadfile` a copy of the new `wow` from HappaTasTest/: no console line, the
classic or new interface as saved, title / Help show 3.0.0; with the old V2 `wow` (`git show b54e1c1:wow`) loaded
first, the new one unloads it (one interface, getgenv `__HappaTAS` nil); Unload leaves no GUI under CoreGui / gethui /
PlayerGui, no camera hook (isfunctionhooked false), no getgenv entry.
- [ ] **Step 3: Criterion 2:** for each `.tas` in the place folder (dzr's own runs, v1-v3): `Crit.playback` with V2
(`git show b54e1c1:wow`) and with the new `wow`; Expected: same frame count and length, root position per frame within
0.05 studs (playback writes the recorded CFrame), the run's length on screen the same.
- [ ] **Step 4: Criterion 3:** a copy of the release with `RootFolder = "HappaTasTest/root"` (sed on the CONFIG line)
and a copy of dzr's Settings.json there: first start writes `HappaTasTest/root/Settings3.json`; every V2 setting and
key binding in it (compare with `Settings.byV2`), the sound keys dropped, Settings.json unchanged.
- [ ] **Step 5: Criteria 1 and 4:** the gate's traces SAME and BENCH / SAVEBENCH OK (from Task 3's gate); live cost =
spec 13's accepted gap (no new measurement unless the release differs in engine code: it doesn't).
- [ ] **Step 6: Restore and verify:** every backed-up file byte-identical, fps cap and quality as found,
HappaTasTest deleted, nothing loaded.
- [ ] **Step 7: Write the spec 13 entry** (criterion 4: met in the mock and for saving; live recording ~0.08 ms a
frame over V2.38.17, accepted by dzr on 2026-11-01) and commit `HappaTAS 3 phase 7: live check and success criteria`
(spec, tools/live/criteria3.lua). Update local CLAUDE.md.
