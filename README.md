# HappaTasPort

HappaTAS as one client-side Luau script: records and replays TAS (tool-assisted speedrun) runs in
Roblox, saving `.tas` files to `HappaTasPort/<PlaceId>/` in the executor workspace.

## Files
- `wow`: the latest script, **HappaTAS V2.36**. This is the one to run.
- `true`, `true real`, `nohboard`: older V2.33 versions. `HappaTAS_Executor-2.lua`: V2.32.
- `src/parts/`: the V2.36 source, split into modules. `bash tools/assemble.sh` joins them into
  `src/HappaTAS_Executor.lua` (byte-for-byte the same as `wow`).
- `tests/`: offline tests with a mock of the Roblox API, run with the `luau` CLI.

## Test
```
bash tools/build_test.sh profiler
cd tests && luau run_profiler.lua
```
