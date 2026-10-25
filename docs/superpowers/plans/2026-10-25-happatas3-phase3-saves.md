# HappaTAS 3 Phase 3 (Saves) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** HappaTAS 3 saves and loads runs: its own file format v6, every V2 file (v1-v5, legacy JSON) through a port of V2's reader, a library of the place's runs with folders and attempts, and its settings converted from V2's `Settings.json`. First phase you can record and save with.

**Architecture:** A new `persist` layer under the engine: byte / value helpers, LZ4, the v6 codec (the timeline's columns written directly), the V2 reader (V2.38.16's decoder, producing V2 frame tables that the timeline already converts), a run loader that keeps data with no plugin yet (client objects, buttons, kit, speed factor, mobile) in carry columns for phase 4, the library, and the settings file. The engine gets a busy guard while a save / load runs on its own thread, and `main` exposes a temporary console API until the phase 5 Library window.

**Tech Stack:** Luau (`buffer`), the phase 1 / 2 kernel and engine (`src2/`), the headless mock (`tests/mock/`), `luau` CLI, bash + python3 build scripts.

**Spec:** `docs/superpowers/specs/2026-10-18-happatas3-rewrite-design.md` (1 criteria 2, 3, 4; 4 layer 5; 6; 10; 11; 12 phase 3; 13 "exact v6 column encodings"). Earlier plans: `docs/superpowers/plans/2026-10-19-happatas3-phase1-skeleton.md`, `2026-10-24-happatas3-phase2-engine-core.md`.

## Global Constraints

- Everything in the phase 1 / 2 plans' Global Constraints still holds (Luau syntax, no network code, sUNC lookups with fallbacks, game code only through `GameCall`, Debug output only with `CONFIG.Debug`, version `"3.0.0-dev"`, no `getfenv` / `setfenv`, never commit `CLAUDE.md` / `claude/`).
- **Reference V2 = `src/parts/` at commit `b1569bd`** (`git show b1569bd:src/parts/p07_codec.lua`, `p08_store.lua`). V2.38.17 did not change the file formats.
- Branch `v3-rewrite`. The working tree also holds V2.38.17's edits (PR #16): commit **only** the files a task lists; never commit `src/parts/`, `wow`, `wow1`, `tests/mock/`, `tests/test_*.lua`, `backups/`. File failures in tests are injected from `tests3` (a `PRE` wrapper around the mock's file globals), not by editing `tests/mock/`.
- Paths: runs in `HappaTasPort/<PlaceId>/` (folders are real subfolders, at most 3 deep); HappaTAS 3's settings in `HappaTasPort/Settings3.json`. **Ruling:** V2's `HappaTasPort/Settings.json` is only read (converted once), never renamed or written, because V2 (`wow`) and HappaTAS 3 (`wow3`) both run until phase 7; renaming it (the spec's `Settings.v2.json`) is left to the phase 7 switch-over.
- Limits (V2's): refuse files over 512 MiB (`CONFIG.MaxFileBytes = 512 * 1024 * 1024`), more than 16,777,216 frames, column width over 64.
- Names: V2's `Store.CleanName` rules exactly (`p08_store.lua:41-65` at `b1569bd`: no control chars or `<>:"/\|?*`, trimmed, no trailing dots / spaces, no leading dots, at most 60 UTF-8 characters, reserved Windows names get `_`). Folder segments use the same rules. Name collisions are case-insensitive (Windows).
- Saving and loading never run inside a pipeline handler: they run on their own thread and yield (`task.wait()`) every 2000 frames.
- Errors from damaged files are caught: every public load / save returns `false, message`; nothing a file contains can stop the script.
- New and changed files keep CRLF line endings, like the rest of `src2/`, `tests3/`, `tools/` (`core.autocrlf` is false; write `\r\n`).
- Live tests (Real MCP; dzr: "Real is always connected"): back up `HappaTasPort/Settings.json` and the place's `.tas` files first, record `getfpscap()` and put it back, save only into `HappaTasPort/<PlaceId>/zz_happatas3_test/`, only read dzr's own files, delete the test folder and the test's `Settings3.json` afterwards, leave `Settings.json` byte-identical.

## Review Focus

1. **An executor without LZ4** (`lz4compress` / `lz4decompress` missing): saving writes an uncompressed v6 file, and a compressed v6 or V2 file still loads through the Lua fallback decompressor. Test in Task 2.
2. **A save that fails halfway** (the temporary file can't be written, reads back shorter, or the real write fails): the old file keeps its bytes, the temporary file is gone, the caller gets a message. Test in Task 4.
3. **Names that differ only in case** (`Run` and `run`, Windows file system): saving an attempt, renaming or moving never overwrites the other file; a case-only rename works. Test in Task 4.
4. **A bad settings file**: V2's `Settings.json` with strings for numbers, unknown names, invalid key names, no `profiler`; a `Settings3.json` that isn't valid JSON. Bad entries fall back to defaults, the damaged file is kept as `Settings3.damaged.json`, nothing errors. Test in Task 6.
5. **Saving or loading at the wrong time** (while recording, while another save / load runs, loading in Test): refused with a status message, the run unchanged; every transition is refused while a save / load runs. Test in Task 5.

---

## File Structure

| File | Responsibility |
|---|---|
| `src2/platform/files.lua` | Executor file functions with protected calls, paths, `cleanName` |
| `src2/persist/bytes.lua` | Growing byte writer, bounds-checked reader (varint, zigzag, f64, strings, raw bytes) |
| `src2/persist/value.lua` | Plain Lua values (nil, booleans, numbers, strings, tables) to bytes and back |
| `src2/persist/lz4.lua` | LZ4 through the executor, Lua fallback decompressor (V2's) |
| `src2/persist/codec6.lua` | File format v6: header, columns, meta |
| `src2/persist/v2reader.lua` | V2.38.16's decoder for v1-v5, the V2.34 LZ4 wrap and legacy JSON slots |
| `src2/persist/run.lua` | Loads any file into a timeline (carry columns, meta), builds a v6 file from a timeline |
| `src2/persist/library.lua` | The place's runs: listing, `library.json`, folders, attempts, sort / search, safe saving, rename / move / delete |
| `src2/persist/settingsfile.lua` | `Settings3.json`: load, convert from V2's `Settings.json`, autosave |
| `src2/persist/persist.lua` | Engine side: save / load on a thread, busy guard, status messages |
| `src2/engine/timeline.lua` | Modify: `meta`, `newLike`, `adopt`, `resize` |
| `src2/engine/settings.lua` | Modify: no sound rows (34), `onAny` |
| `src2/engine/controls.lua` | Modify: `changed` listeners |
| `src2/engine/modes.lua` | Modify: refuse transitions while busy, `runLoaded` |
| `src2/config.lua`, `src2/modules.txt`, `src2/main.lua` | Modify: limits, module order, wiring, temporary API |
| `tools/make_v2_fixtures3.sh`, `tests3/fixtures/v2/*` | V2 files and V2's own decode of them |
| `tools/trace3.sh`, `tests3/trace/*` | Modify: save / load parity |
| `tools/savebench3.sh`, `tests3/bench/save.lua` | 10-minute save / load time and size, V2 vs HappaTAS 3 |
| `tests3/test_bytes.lua`, `test_codec6.lua`, `test_v2reader.lua`, `test_persist.lua`, `test_library.lua`, `test_settingsfile.lua`, `test_settings.lua`, `test_main.lua` | One suite per task |

`.gitignore` additions: `tests3/fixtures/local/`, `tests3/trace/v2file.lua`, `tests3/bench/run_*.lua`.

**File-failure helper for tests (`tests3/fsfail.lua`, prepended with `PRE`):** wraps the mock's `writefile`, `readfile`, `listfiles` before the script boots; `FSFAIL = { write = pattern, read = pattern, short = pattern, log = {} }` makes a matching write error, a matching read error, a matching read return all but the last byte, and logs every call as `{ op, path }`.

---

### Task 1: Files, bytes and values

**Files:**
- Create: `src2/platform/files.lua`, `src2/persist/bytes.lua`, `src2/persist/value.lua`, `tests3/fsfail.lua`, `tests3/test_bytes.lua`
- Modify: `src2/modules.txt` (after `platform/env`: `platform/files`; a `persist/` block after `engine/timeline`: `persist/bytes`, `persist/value`)

**Interfaces:**
- Produces:
  - `Files.new(Env) -> F`. `F.available: boolean` (Env.has("files")). Methods return `nil / false, message` on failure, never error: `F:read(path) -> string?`, `F:write(path, s) -> boolean, err?`, `F:exists(path)`, `F:isFolder(path)`, `F:makeFolder(path)` (creates missing parents), `F:listFiles(folder) -> { names }`, `F:listFolders(folder) -> { names }`, `F:delete(path) -> boolean, err?`.
  - `Files.cleanName(s) -> string?` (V2 rules, Global Constraints), `Files.join(...) -> string` (`/` separated).
  - `Bytes.writer() -> W`: `W:u8(n)`, `W:varint(n)` (0 .. 2^53), `W:zigzag(n)`, `W:f64(x)`, `W:str(s)` (varint length + bytes), `W:raw(s)`, `W:rawBuffer(buf, offset, len)`, `W:len()`, `W:tostring()`. Backed by a `buffer` that doubles.
  - `Bytes.reader(s, pos = 1, last = #s) -> R`: `R:u8()`, `R:varint()`, `R:zigzag()`, `R:f64()`, `R:str()`, `R:raw(n)`, `R:pos()`, `R:left()`. Reading past `last`, a varint over 2^53 or a string longer than what is left errors `"file is damaged: <what>"`.
  - `Value.write(W, v)`, `Value.read(R) -> v`: tags 0 nil, 1 false, 2 true, 3 non-negative integer (varint), 4 negative integer (zigzag), 5 f64, 6 string, 7 table (varint array count, values; varint hash count, key / value pairs). Other types error `"can't save a <type>"`; tables nested deeper than 64 (or a cycle) error `"table nested too deep"`.

- [ ] **Step 1: Write `tests3/fsfail.lua` and the failing suite `tests3/test_bytes.lua`**

```lua
local Bytes, Value, Files = __T3("persist/bytes"), __T3("persist/value"), __T3("platform/files")
local w = Bytes.writer()
w:u8(255); w:varint(0); w:varint(2^53); w:zigzag(-123456789); w:f64(-0.0); w:f64(1/3); w:str("héllo\0x")
local r = Bytes.reader(w:tostring())
eq(r:u8(), 255, "u8"); eq(r:varint(), 0, "varint 0"); eq(r:varint(), 2^53, "varint 2^53")
eq(r:zigzag(), -123456789, "zigzag"); eq(1 / r:f64(), -math.huge, "-0 kept"); eq(r:f64(), 1/3, "f64 exact")
eq(r:str(), "héllo\0x", "string with a zero byte"); eq(r:left(), 0, "all read")
check(not pcall(function() Bytes.reader("\255"):varint() end), "a cut varint errors")
check(select(2, pcall(function() Bytes.reader("\5ab"):str() end)):find("file is damaged"), "a string longer than the file errors")
local v = { 1, -2, 3.5, "x", true, false, { a = { b = { c = 1 } } }, [10] = "sparse", k = 2^40 }
local w2 = Bytes.writer(); Value.write(w2, v)
check(deepEqual(Value.read(Bytes.reader(w2:tostring())), v), "a table round-trips")
check(not pcall(Value.write, Bytes.writer(), { workspace }), "an Instance is refused")
local cyc = {}; cyc.self = cyc
check(not pcall(Value.write, Bytes.writer(), cyc), "a cycle is refused")
eq(Files.cleanName("  ../a<b>|c?.  "), "abc", "cleaned like V2 (characters removed, dots / spaces trimmed)")
eq(Files.cleanName("CON"), "_CON", "reserved name")
eq(Files.cleanName(string.rep("é", 70)), string.rep("é", 60), "60 characters")
FSFAIL.write = "fail%.txt"
local F = Files.new(__T3("platform/env"))
local ok, err = F:write("HappaTasPort/fail.txt", "x")
check(not ok and type(err) == "string", "a failing write returns false, message")
```

Add `deepEqual(a, b)` to the top of the suite (numbers compared exactly, NaN equal to NaN). The `cleanName` literals match V2's `Store.CleanName` (b1569bd); check any new case by running V2's function on it.

- [ ] **Step 2: Run it: fails (modules missing)**

Run: `PRE="$(cat tests3/fsfail.lua)" bash tools/build_test3.sh bytes && (cd tests3 && luau run_bytes.lua)`
Expected: FAIL, `import` of `persist/bytes` errors.

- [ ] **Step 3: Implement the three modules** (signatures above). `Files` wraps each executor call in `pcall`; `listFiles` / `listFolders` split `listfiles` results with `isfolder`; names are the last path segment.

- [ ] **Step 4: Run it: passes; `bash tools/test_all3.sh` stays green**

Make `tools/test_all3.sh` prepend `tests3/fsfail.lua` as `PRE` for every suite whose file starts with `-- needs: fsfail` (first line of the suite).

- [ ] **Step 5: Commit** `src2/platform/files.lua src2/persist/bytes.lua src2/persist/value.lua src2/modules.txt tests3/fsfail.lua tests3/test_bytes.lua tools/test_all3.sh` — "HappaTAS 3: files, bytes and values for saving"

---

### Task 2: LZ4 and file format v6

**Files:**
- Create: `src2/persist/lz4.lua`, `src2/persist/codec6.lua`, `tests3/test_codec6.lua`
- Modify: `src2/engine/timeline.lua`, `src2/config.lua` (`MaxFileBytes = 512 * 1024 * 1024`, `MaxFrames = 16777216`), `src2/modules.txt`, `tests3/test_timeline.lua`

**Interfaces:**
- Consumes: `Bytes`, `Value` (Task 1); `Timeline` (phase 2).
- Produces:
  - Timeline: `tl.meta` (table, `{}` from `new`), `Timeline.newLike(tl) -> tl2` (same columns, no frames, meta `{}`), `tl:adopt(other)` (takes `other`'s buffers, lists, count and meta; `version + 1`), `tl:resize(n)` (count `n`, capacity at least `n`, frames marked filled, lists cleared, `version + 1`).
  - `Lz4.compress(s) -> string?` (nil without `Env.lz4compress` or when it errors), `Lz4.decompress(s, size) -> string` (executor first; else the Lua port of V2's `lz4Fallback`, `p07_codec.lua:123-162` at b1569bd; a result of another size errors `"file is damaged: size"`).
  - `Codec6.encode(tl, header, progress?) -> string`; `Codec6.readHeader(data) -> header? , err?` (no decompression); `Codec6.decode(data, tl, progress?) -> header` (errors on damage). `progress(done, total)` is called every 2000 frames, and the call yields with `task.wait()` when `coroutine.isyieldable()`.

**Format v6 (the spec's 13 open question, decided here):**

```
"HTAS"  u8 6  u8 flags (bit 0 = body is LZ4)
varint headerLen, Value table { frames, length, created, saved, script, place, kit, speedHack, name }
varint rawLen, body (LZ4 block of rawLen bytes, or rawLen raw bytes)
body = varint columnCount, then per column: str name, u8 kind (1 f64, 2 u8, 3 list), u8 width,
       varint byteLen, payload; then Value meta (tl.meta)
f64 payload (lossless): per component, each frame's 8 bytes XOR the previous frame's (frame 1 XOR 0), then
       split into 8 byte planes (all frames' byte 0, then all byte 1, ...): slow-changing numbers become
       long runs that LZ4 packs
u8 payload: the frames' bytes
list payload: varint entries, then per entry: varint frame - previous entry's frame (first: frame), Value
```

The file's columns are matched to the timeline's by name. A column the timeline lacks is added (no `v2`) so it round-trips; a timeline column the file lacks stays zero / nil; a column with another kind or width errors `"column <name> has a different shape"`. The internal `_filled` column is not written (loaded frames are filled).

- [ ] **Step 1: Write the failing suite `tests3/test_codec6.lua`** (and the Timeline additions' tests in `test_timeline.lua`: `newLike` copies columns but not frames, `adopt` moves everything and bumps `version`, `resize`)

```lua
local tl = makeTimeline(5000)  -- helper in the suite: every kind, random walk values, -0, NaN, 1e300, lists with tables / strings / gaps
tl.meta = { created = 1761400000, v2kit = { version = 1, keys = { { 1, "a" } } } }
local hdr = { frames = 5000, length = 20.8, created = 1, saved = 2, script = "3.0.0-dev", place = 72164126024589, kit = 1, speedHack = 0, name = "x" }
local data = Codec6.encode(tl, hdr)
local back = Timeline.newLike(tl); Codec6.decode(data, back)
check(sameBits(tl, back), "every column bit for bit (NaN, -0 too)")
check(deepEqual(back.meta, tl.meta), "meta")
check(deepEqual(Codec6.readHeader(data .. "garbage-after"), hdr), "header without the body")
check(Codec6.readHeader(data:sub(1, 30)) ~= nil, "header readable from the first bytes")
-- every truncation errors, never returns frames
for cut = 7, #data - 1, 97 do check(not pcall(Codec6.decode, data:sub(1, cut), Timeline.newLike(tl)), "cut at " .. cut) end
check(select(2, pcall(Codec6.decode, "HTAS\7" .. data:sub(6), Timeline.newLike(tl))):find("unsupported"), "version 7")
-- an unknown column round-trips; a wrong shape errors
-- without LZ4 (PRE: lz4compress = nil): flags bit 0 clear, loads; with lz4decompress = nil: the fallback loads a compressed file
-- in a coroutine, encoding 5000 frames yields at least twice and progress ends at (5000, 5000)
check(#data < 0.25 * 5000 * rawBytesPerFrame(tl), "smaller than a quarter of the raw columns")
```

Run the "without LZ4" parts as a second build: `tests3/codec6.variants` (like `platform.variants`) with `PRE='lz4compress = nil'` and `PRE='lz4decompress = nil'`.

- [ ] **Step 2: Run: fails** — `bash tools/build_test3.sh codec6 && (cd tests3 && luau run_codec6.lua)`, Expected: FAIL (module missing).

- [ ] **Step 3: Implement** `Lz4`, `Codec6`, the Timeline methods. The XOR uses `buffer.readu32` on the two halves of each f64.

- [ ] **Step 4: Run: passes**, variants too (`bash tests3/run_variants.sh codec6`); `bash tools/test_all3.sh` green.

- [ ] **Step 5: Commit** — "HappaTAS 3: file format v6 (lossless columns, header readable without the body)"

---

### Task 3: The V2 reader

**Files:**
- Create: `src2/persist/v2reader.lua`, `tools/make_v2_fixtures3.sh`, `tests3/fixtures/v2/` (generated, committed), `tests3/test_v2reader.lua`
- Modify: `src2/modules.txt`, `.gitignore`

**Interfaces:**
- Consumes: `Bytes` (optional; the port may keep V2's own reader helpers), `Lz4.decompress` (Task 2), `Env.svc("HttpService")` for JSON.
- Produces: `V2Reader.read(data, progress?) -> result` with `result = { frames = { V2 frame tables }, objects, buttons, kit, version (1-5, 0 = legacy JSON), kitVersion }`; errors on damage. Covers: the V2.34 wrap `"\0LZ4\1"` + u32 size (`p08_store.lua` LoadSlot), binary v1-v5 (`p07_codec.lua` Decode and helpers, lines 30-170 and 535-824), legacy JSON slots (`p08_store.lua` `unpackFrame`, `validFrame`, `loadLegacyJson`, lines 121-141 and 190-230; result `kitVersion = 0`). A port: same results, `CONFIG` / `Env` names adapted, no other changes.

- [ ] **Step 1: Write `tools/make_v2_fixtures3.sh`**

It builds a luau runner from the reference V2 (`git show b1569bd:src/parts/...` assembled the way `tools/trace3.sh` builds `tests3/trace/ref/`), records three runs in the mock with V2 itself (plain walk + jump; client objects + a button press; kit events + speed hack 0.5x), saves each with V2's `Store.SaveSlot`, and writes for each file `tests3/fixtures/v2/<name>.tas` and `<name>.expected.lua` (`return { frames = ..., objects = ..., buttons = ..., kit = ... }` from V2's `Codec.Decode`, numbers printed with `%.17g`). It also derives version variants from each v5 file (`v1`: the first 21 columns, `v2`: 23, `v3`: 29, `v4`: 29 with byte 5 = 4; body recompressed with the mock's LZ4, rawLen updated) and records V2's decode of each variant (or its error text), plus one legacy JSON slot (batches layout) and one V2.34-wrapped copy. Files stay under 64 KiB each. The runner prints each file as hex; the script turns that into binary files (python3).

- [ ] **Step 2: Write the failing suite `tests3/test_v2reader.lua`**

```lua
for name in pairs(FIXTURES) do
  local data, expected = FIXTURES[name].data, FIXTURES[name].expected
  local ok, got = pcall(V2Reader.read, data)
  if expected.error then check(not ok, name .. ": V2 refused it too")
  else check(ok and deepEqual(got.frames, expected.frames) and deepEqual(got.objects, expected.objects)
      and deepEqual(got.buttons, expected.buttons) and deepEqual(got.kit, expected.kit), name .. ": same as V2's decoder") end
end
-- 300 single-byte flips of the v5 fixture: read returns or errors within 2 s each, never hangs
```

Extend `tools/build_test3.sh`: for a suite whose first line is `-- needs: v2fixtures`, prepend `FIXTURES = { [name] = { data = "<the .tas bytes as an escaped Lua string>", expected = (function() <the .expected.lua file> end)() } }` for every file in `tests3/fixtures/v2/`.

- [ ] **Step 3: Run: fails** (module missing). **Step 4: Port the reader**, run: passes; 300 flips: no hang.
- [ ] **Step 5: Commit** — "HappaTAS 3: V2 file reader (v1-v5, legacy JSON), checked against V2's own decoder"

---

### Task 4: The library

**Files:**
- Create: `src2/persist/library.lua`, `tests3/test_library.lua`
- Modify: `src2/modules.txt`

**Interfaces:**
- Consumes: `Files` (Task 1), `Codec6.readHeader` (Task 2), V2 header fields (`HTAS`, version 1-5, varint frames: read with `Bytes`).
- Produces: `Library.new(files, root) -> L` (`root = "HappaTasPort/<PlaceId>"`).
  - `L:list() -> { entry }`, entry = `{ path, name, folder, ext, size, frames, length, created, saved, script, kit, speedHack, version, attempt, base }` (`path` relative to root, `/`-separated; V2 files: `frames` from their header, the rest nil until loaded once). Reads only files missing from `root/library.json` (`{ version = 1, entries = { [path] = info } }`), drops entries whose file is gone, writes the cache back when it changed. `L:refresh()` re-reads every header. `.tas` and legacy `.json` slots are listed; `library.json`, `*.tmp`, `*~rename*` are not.
  - `L:sorted(entries, by = "name" | "date" | "length", descending?)` (names by V2's natural key, `p08_store.lua:80-85`); `L:search(entries, text)` (case-insensitive substring of the name).
  - `L:groups(entries) -> { { run = entry, attempts = { entry } } }`: `"X (n)"`, n >= 2, in the same folder as an existing `"X"` is an attempt of it; attempts newest first (higher n first).
  - `L:nextAttemptName(name, folder) -> "name (k)"`, k = 1 + the highest existing (at least 2), compared case-insensitively.
  - `L:save(name, folder, data) -> ok, err`: `<path>.tmp` written and read back (same length), then the real file written and read back, then the `.tmp` deleted; a legacy `.json` of the same name is deleted after (V2 did); the cache entry updated from the new header. Any failure: the old file keeps its bytes, the `.tmp` is deleted, `false, message`.
  - `L:read(path) -> data?, err`, `L:rename(path, newName)`, `L:move(path, folder)` (refused when the target exists, case-insensitively, unless it is the same file; a case-only rename goes through `<name>~rename<ext>` like V2), `L:delete(path)`, `L:createFolder(folder)`, `L:deleteFolder(folder)` (empty folders only), at most 3 folder levels, every segment through `Files.cleanName`.

- [ ] **Step 1: Write the failing suite** (`-- needs: fsfail`): mixed v6 / v5 / JSON files in the root and two folders; second `list()` reads no `.tas` (FSFAIL.log); a deleted file disappears from the cache; attempts `Run`, `Run (2)`, `Run (3)` grouped newest first, `nextAttemptName("run")` is `"run (4)"`; sort by date / length / name (`Run 2` before `Run 10`); search `"RUN"`; Review focus 2 (FSFAIL.write = `%.tmp$`, FSFAIL.short = `%.tmp$`, FSFAIL.write on the real path: old bytes kept, no `.tmp` left); Review focus 3 (`Run` exists, saving / renaming / moving `run` refused, `Run` -> `RUN` works); `"../evil"` stays inside the root; deleting a non-empty folder refused.
- [ ] **Step 2: Run: fails.** **Step 3: Implement.** **Step 4: Run: passes.**
- [ ] **Step 5: Commit** — "HappaTAS 3: library of runs (folders, attempts, safe saving)"

---

### Task 5: Loading and saving a run in the engine

**Files:**
- Create: `src2/persist/run.lua`, `src2/persist/persist.lua`, `tests3/test_persist.lua`
- Modify: `src2/engine/modes.lua`, `src2/modules.txt`

**Interfaces:**
- Consumes: `Codec6` (Task 2), `V2Reader` (Task 3), `Library` (Task 4: `read`, `save`, `nextAttemptName`), `Timeline` additions (Task 2), `Modes` (phase 2).
- Produces:
  - `Run.registerCarry(tl)`: for each V2 key `Mobile`, `CO`, `BT`, `KE`, `SK` that no column claims (`v2.key`), adds list column `"v2" .. key` with `{ key = key, keep = true }`. Called once in `main` after the plugins added their columns.
  - `Run.load(tl, data, progress?) -> header`: v6 → `Codec6.decode`; `HTAS` v1-v5, the V2.34 wrap, JSON → `V2Reader.read`, then `tl:replaceFromV2(frames)` and `tl.meta = { v2objects, v2buttons, v2kit, kitVersion, source = "v<version>" }`. Returns a header built the same way for V2 files (`created` / `saved` nil). Errors on damage.
  - `Run.build(tl, name) -> data`: `Codec6.encode` with header `{ frames, length = last TotalTime, created = tl.meta.created or now, saved = now, script = CONFIG.VERSION, place = game.PlaceId, kit = tl.meta.kitVersion or 0, speedHack = (any v2SK value ~= nil) and 1 or 0, name }`; sets `tl.meta.created`.
  - `Persist.new(E) -> P`: `P:save(name, folder?, asAttempt?) -> ok, message` and `P:load(path) -> ok, message`. Both start a thread (`task.spawn`) and return at once with `true, "started"` or refuse with `false, reason`; `E.busy` = `"saving"` / `"loading"` while it runs; the result is published on the bus (`"persist", { op, ok, message, path }`) and as a status message (`"Saved <name>"`, `"Loaded <name>"`, the error). A load decodes into `Timeline.newLike(E.tl)` and only on success `E.tl:adopt(...)` then `E.modes:runLoaded()`; a failed load leaves the run as it was.
  - Refusals: save while Recording (`E.mode == 2` and not paused), load unless Idle or Paused (Create), both while `E.busy`, both when files are unavailable (`"Saving is unavailable on this executor"`).
  - `Modes:allowed(...)` returns false for every transition while `E.busy`; `Modes:runLoaded()` does what `setRun` does after the frames are in (frame = last, `loadFrame` in Create, publish, `lastPause`).

- [ ] **Step 1: Write the failing suite `tests3/test_persist.lua`** (uses the Task 3 fixtures and `fsfail`)

```lua
-- a V2 file into the engine: phase 2 columns and the carry columns give back V2's frames
-- (the fixture files are copied into the mock place folder first)
local ok = E.persist:load("kitspeed.tas"); waitFor(function() return not E.busy end)
check(deepEqual(E.tl:toV2All(), expected("kitspeed").frames), "V2 frames back from the timeline")
check(deepEqual(E.tl.meta.v2kit, expected("kitspeed").kit), "kit table kept")
-- save as v6, load it again: every column the same, carry columns too
-- Review focus 5: recording -> save refused, run unchanged; Test -> load refused; while saving: Unpause / Idle / Delete refused
-- a damaged file: load returns through the bus with ok = false, E.tl is the same object with the same version
```

- [ ] **Step 2: Run: fails.** **Step 3: Implement.** **Step 4: Run: passes; `bash tools/test_all3.sh` green (trace still SAME).**
- [ ] **Step 5: Commit** — "HappaTAS 3: load and save runs (V2 files keep their client object / kit data for phase 4)"

---

### Task 6: Settings file

**Files:**
- Create: `src2/persist/settingsfile.lua`, `tests3/test_settingsfile.lua`, `tests3/fixtures/settings_v2.json` (dzr-like: every V2 name including the 5 sound settings, every control, a `profiler` table)
- Modify: `src2/engine/settings.lua` (remove the 5 sound rows: 34 rows; add `Settings:onAny(f)`, `f(key, value)` after any change, returns a remover), `src2/engine/controls.lua` (`Controls:changed(f)`, `f(control, keyName)` after `set` changed a value, returns a remover), `src2/modules.txt`, `tests3/test_settings.lua` (34 rows, sound names gone)

**Interfaces:**
- Consumes: `Files` (Task 1), `Settings`, `Controls`, `Keys.isValid` (phase 2), `Env.svc("HttpService")`, the kernel lifecycle scope.
- Produces: `SettingsFile.new(files, settings, controls, life) -> SF`.
  - `SF:load() -> source`: `"v3"` from `HappaTasPort/Settings3.json` (`{ format = "HappaTAS3 settings", version = 1, settings = { [key] = v }, controls = { [control] = keyName }, profiler = table? }`); `"v2"` converted from `HappaTasPort/Settings.json` (V2 names through `Settings.byV2` / `Controls.byV2`; unknown names, the sound names included, ignored; values through `Settings.sanitize`; key names through `Keys.isValid` or `"None"`; `profiler` kept) and written to `Settings3.json` at once; `"defaults"` when neither exists; a `Settings3.json` that isn't a valid table is renamed to `Settings3.damaged.json` first (source `"v2"` / `"defaults"` after it). `Settings.json` is never written.
  - `SF.profiler` (the `profiler` table or nil, for phase 6); `SF:setProfiler(t)` (queues a save).
  - Autosave: any `onAny` / `changed` / `setProfiler` queues one save 0.4 s later (`task.delay`); `SF:flush()` writes now when one is queued; the lifecycle scope flushes on cleanup before the engine is undone.

- [ ] **Step 1: Write the failing suites** (`-- needs: fsfail`): converted values and controls equal the fixture's (with the 5 sound names gone and no errors reported); `Settings.json` byte-identical after load and after changes; a second boot reads `"v3"` even after `Settings.json` changes; Review focus 4 (`"Playback Speed": "fast"` -> default, `"Stats Text Size": 999` -> 30, `"Pause": "Banana"` -> default key, no `profiler` -> nil, a damaged `Settings3.json` kept as `.damaged.json`); five changes within 0.1 s -> one write 0.4 s later; a change then Unload within 0.4 s -> written (FSFAIL.log).
- [ ] **Step 2: Run: fails.** **Step 3: Implement.** **Step 4: Run: passes; `test_settings` updated and green.**
- [ ] **Step 5: Commit** — "HappaTAS 3: settings file (converted from V2's Settings.json, autosave, sounds dropped)"

---

### Task 7: Wiring and the temporary console API

**Files:**
- Modify: `src2/main.lua`, `src2/modules.txt`, `tests3/test_main.lua`

**Interfaces:**
- Consumes: Tasks 1-6 (Task 4 library, Task 5 run / persist).
- Produces: in `startEngine`: `E.files = Files.new(Env)`; `E.settingsFile = SettingsFile.new(E.files, E.settings, E.controls, life)` and `:load()` right after `Settings.new` / `Controls.new` (before any plugin starts); `Run.registerCarry(E.tl)` after the plugins added their columns; `E.library = Library.new(E.files, "HappaTasPort/" .. game.PlaceId)`; `E.persist = Persist.new(E)`. The shared handle gets (until the phase 5 Library window, said so in a comment): `handle.Save(name, folder?) -> ok, message`, `handle.SaveAttempt(name, folder?)`, `handle.Load(path) -> ok, message`, `handle.List() -> { { path, name, frames, length, saved } }`. Without file functions every one of them returns `false, "Saving is unavailable on this executor"` and the script runs.

- [ ] **Step 1: Write the failing tests** in `test_main.lua`: record 120 frames, `Save("a")`, Idle, `Load("a.tas")`, Test plays to the end with the same final root position as before saving; `List()` shows `a` with 120 frames; with `PRE='writefile = nil'` the script boots, `Save` returns the message, no error in the logs; Unload flushes a queued settings save.
- [ ] **Step 2: Run: fails.** **Step 3: Implement.** **Step 4: Run: passes; `bash tools/test_all3.sh` green.**
- [ ] **Step 5: Commit** — "HappaTAS 3: saves wired into the engine, temporary console API"

---

### Task 8: Trace parity after saving and loading

**Files:**
- Modify: `tools/trace3.sh`, `tests3/trace/scenario.lua`, `tests3/trace/adapter_v2.lua`, `tests3/trace/adapter_v3.lua`, `.gitignore`

**Interfaces:**
- Consumes: V2's `Store.SaveSlot` / `Store.LoadSlot` (reference build), `E.persist` (Task 5) through the adapters.
- Produces: scenario part B after the existing session: save the run, Idle, Delete, load it, Test to the end (both builds, each with its own format). Part C (V3 only): load the file V2 saved in part B (the V2 run prints it as `V2FILE <hex>`; `trace3.sh` writes `tests3/trace/v2file.lua`) and Test; its trace is compared with V2's part B Test.

- [ ] **Step 1: Add parts B and C; run `bash tools/trace3.sh`.** Expected before the adapters are done: a difference or a missing section. **Step 2: Finish the adapters.** Expected: `SAME` for every field in `P2FIELDS`, all three parts.
- [ ] **Step 3: Commit** — "HappaTAS 3: trace parity after save / load, V2 files play like in V2"

---

### Task 9: Save time and file size against V2

**Files:**
- Create: `tools/savebench3.sh`, `tests3/bench/save.lua`
- Modify: `tools/test_all3.sh` (run it with `BENCH=1` only)

**Interfaces:**
- Consumes: V2's `Codec.Encode` / `Decode` (reference build), `Run.build` / `Run.load` (Task 5).
- Produces: a 10-minute run (144,000 frames at 240 FPS, walking, turning, jumping, a key and the mouse every few frames) built the same way in both builds; prints `V2 save <ms> <bytes>`, `V3 save <ms> <bytes>`, the same for load.

- [ ] **Step 1: Write the bench; run** `bash tools/savebench3.sh`. Gate (spec criterion 4): V3 save time < V2 save time. If it fails, profile the XOR / plane loop first (one `buffer.copy` per plane row, no table per frame) before any format change; a format change needs a `Ruling:` and dzr's OK.
- [ ] **Step 2: Write the measured sizes and times into the spec's section 13 answer** (replace the "Exact v6 column encodings" open question with the result).
- [ ] **Step 3: Commit** — "HappaTAS 3: save / load bench against V2"

---

### Task 10: Release build and live check

**Files:**
- Modify: `docs/superpowers/specs/2026-10-18-happatas3-rewrite-design.md` (only if Task 9 or the live check changes an answer), `wow3` (built, not committed: build output)

- [ ] **Step 1: `bash tools/build3.sh` and `bash tools/test_all3.sh`** — every suite, variants, trace, release start / unload: green.
- [ ] **Step 2: Live (Real MCP), following the Global Constraints' live rules:** load the release from `HappaTasTest/`; `Settings3.json` appears with dzr's values converted, `Settings.json` hash unchanged; record ~5 s, `Save("live", "zz_happatas3_test")`, Unload, run again, `List()` shows it with frames / length / saved, `Load`, Test: the final root position equals the recorded one within 0.001; `Load` each of dzr's V2 files (read only) and Test 2 s: no console errors; save time of the 5 s run; Unload leaves nothing (phase 1 check).
- [ ] **Step 3: Clean up** (test folder, the test's `Settings3.json`, fps cap) **and commit** any spec answer — "HappaTAS 3 phase 3: live check".
