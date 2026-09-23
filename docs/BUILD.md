# Build

## Side-load on device

For direct sideloading to a watch, the file MUST be a `.prg` produced by the
"build for device" flow — NOT a `.iq` file. The `.iq` cannot be used for
sideloading.

Example:

```
monkeyc -d <device> -f monkey.jungle -o <app>.prg -y developer_key.der -w
```

Current build: `ebikedf.prg` (in project root).

## Local simulator

For the simulator, use `.iq` builds. The `.iq` files in `bin/` are for that
purpose.