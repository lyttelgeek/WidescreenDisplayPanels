# Changelog


## 1.2.1 - Wired Ports Patch

### Features:
- "Output" ports now directly wired to panels' "input" sides, enabling bidirectional passthrough and signal input from either side

### UI:
- Slightly increased main window width
- Moved smart logic control to vanilla-style "circuit network" pop-out sub-window
- Tweaked signal bar to as closely match vanilla combinator gui as possible
- Removed but one custom gui button sprite

### Fixes:
- Fixed remnants spawning and ports remaining when mining panels on space platforms
- Changed right/bottom ports to direct input wiring to better prevent count looping and enable input from either side (removed 'write_const')
- Fixed quality overlays not appearing on signal bar

---

## 1.2.0 - Smartscreen Update

### Features
- Added smart logic system per segment:
  - Enable via the "Enable smart logic" toggle in the segment GUI
  - **Arithmetic A → Arithmetic B pipeline**: two chained arithmetic combinators; enabling Arithmetic B unlocks Arithmetic A for upstream pre-processing
  - **Decider combinator**: independent of the arithmetic pipeline; output merges with arithmetic result (decider wins on collision)
  - Signal flow: panel input → Arithmetic A → Arithmetic B → segment display rules
  - Smart combinators open their native Factorio GUI for full configuration
  - Combinator configuration is preserved when toggling on/off

### UI
- Signal bar now shows red and green wire signals in separate rows
- Signal bar uses vanilla-style scrollbar; expands to 4 rows before scrolling
- Smart logic master toggle no longer affects signal bar display; only active sub-combinators do

### Recipes
- All panels now include 3 combinator sets (arithmetic, decider, constant) per segment in their recipe:
  - 2×1 / 1×2: 2 iron plate, 32 electronic circuit, 30 copper wire
  - 3×1 / 1×3: 3 iron plate, 48 electronic circuit, 45 copper wire
  - 4×1 / 1×4: 4 iron plate, 64 electronic circuit, 60 copper wire

### Fixes
- Fixed smart combinator wire connection triangles appearing on the main surface
- Fixed smart feeder only connecting via red wire (green was ignored)
- Fixed signal bar merging red and green onto green when smart master was toggled

---

## 1.1.0 - Tallscreen Update

### Features
- Added tallscreen display panels (1x2, 1x3, 1x4)
- Same behaviour as widescreen panels
- Vertical icon/message layout
- Signal input at top, output connector at bottom

### UI
- Refined GUI to better match vanilla style
- Improved layout, spacing, and alignment
- Updated and cleaned up icons

### Changes
- Renamed "Show in alt mode" to "Always show in Alt-Mode"

### Fixes
- Fixed message text scaling when alt-mode display is disabled
- Fixed item signal icons not rendering on panels

---

## 1.0.0 - Initial Stable Release

### Features
- Initial release
- Added widescreen display panels (2x1, 3x1, 4x1)
- Segment-based display system
- Multiple rules per segment
- Icon and message rendering
- Alt-mode visibility option
- Chart tag support

### Integration
- Compatible with Display Signal Counts (DSC)

### UI
- Custom configuration GUI
- Segment tabs and rule editor
- Message editor with icon insertion

### Quality of Life
- Copy and paste segment settings

### Technical
- Persistent GUI state across save/load
- Improved message background sizing for rich text
- Stable runtime behaviour and rendering
