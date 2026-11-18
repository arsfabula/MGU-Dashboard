# Build

## Side-load on device

For direct sideloading to a watch, the file MUST be a `.prg` produced by the
"build for device" flow — NOT a `.iq` file. The `.iq` cannot be used for
sideloading.

Example:

```
monkeyc -d <device> -f monkey.jungle -o <app>.prg -y developer_key.der -w
```

Builds are **throwaway artifacts** — a `.prg` is only useful for sideloading on a
watch, a `.iq` only for the local simulator. Write them to a scratch folder (for
example `%TEMP%\opencode\`): `*.prg`, `*.iq` and `bin/` are already ignored by
`.gitignore`, so no build output is ever committed, and no `.prg` on disk is a
reference for anything.

Build with the SDK referenced in `docs/HANDOFF-NOUVELLE-SESSION.md` §1 (currently
`connectiq-sdk-win-9.3.0-2026-10-20-95888f262`). Measured sizes only compare at
the same SDK version — changing SDK shifts them (~200 B here).

## Local simulator

For the simulator, use `.iq` builds. The `.iq` files in `bin/` are for that
purpose.