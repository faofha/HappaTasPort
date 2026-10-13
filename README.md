# HappaTasPort

HappaTAS as one client-side Luau script: records and replays TAS (tool-assisted speedrun) runs in
Roblox, saving `.tas` files to `HappaTasPort/<PlaceId>/` in the executor workspace.

## Files
- `wow`: the latest script, **HappaTAS V2.37**. This is the one to run. It is the release build: the
  same code as the source, without comments and blank lines.
- `true`, `true real`, `nohboard`: older V2.33 versions. `HappaTAS_Executor-2.lua`: V2.32.
- `src/parts/`: the source with comments, split into modules. `bash tools/assemble.sh` joins them into
  `src/HappaTAS_Executor.lua`; `bash tools/release.sh` writes `wow` from it.
- `tests/`: offline tests with a mock of the Roblox API, run with the `luau` CLI.

## Test
```
bash tools/test_all.sh                 # every suite (headless mock, not a real game)
bash tools/diff_builds.sh old.lua      # same behaviour as an older build? (frame-by-frame traces)
bash tools/build_test.sh bench && cd tests && luau run_bench.lua   # cost per frame in every mode
```
