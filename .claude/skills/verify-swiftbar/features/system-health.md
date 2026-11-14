# System health

The fourth title line shows the average SoC die temperature and free disk space (`46°C · 💾 43% free`), with `⚠️ disk` or `⚠️ battery` added when something is wrong. The dropdown shows `SoC temp · avg · max`, `Disk · SMART <status> · <free> free (<pct>%)` (red when SMART isn't `Verified`/`Not Supported` or the disk is over 90% full), and `Battery · <health>% health · <cycles> cycles` (red when health is below 80% or a permanent failure is flagged).

## Sub-features

- `health-temp`: average and max over the `tdie` IOKit sensors.
- `health-disk`: free percent on `/System/Volumes/Data`, plus the SMART status of `disk0`.
- `health-battery`: health is nominal ÷ design capacity, plus the cycle count.
- `health-alerts`: `⚠️` flags in the title and `color=red` in the dropdown.

## How to get to it (user POV)

- Menu bar title, fourth rotating line
- Dropdown, the `SoC temp`, `Disk`, and `Battery` lines

## Driving it with verify.sh

Preconditions:

- Any run-id, on Apple silicon. Battery lines need a laptop.

- **Disk.** Run `$V run $RUN baseline`, then `$V check $RUN baseline`. `disk_free_percent` is `MATCH` (within 1 point). `Disk · SMART` matches `diskutil info disk0 | grep 'SMART Status'`.
- **Temperature.** `temp_avg` is `SANE`. Repeat the run under load (a build); the average should rise.
- **Battery.** `ioreg -rn AppleSmartBattery | grep -E '"(DesignCapacity|NominalChargeCapacity|CycleCount)" ='`. Health is `nominal*100/design`, rounded down, and matches the `Battery ·` line.
- **Alerts.** The real hardware is healthy, so the alert paths can't be reached here. They're covered by stubs in `tests/prodwatch.bats` (`flags a failing SMART status`, `flags a disk over 90% full`, `flags battery health below 80%`). Report them as test-covered, not live-verified.

## Gotchas

- The temperature reader is inline Python calling private IOKit HID APIs. If the sensors aren't found, the temperature disappears from the title with no error (stderr goes to `/dev/null` in the plugin). `MISSING` on `temp_avg` means the reader broke, not that the machine is cold.
- `df` and the oracle both read `/System/Volumes/Data`, not `/`. On APFS, `/` is the sealed system volume and shows almost no usage.
