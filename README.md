# Widescreen Display Panels

Adds 2x1, 3x1, and 4x1 widescreen variants of the vanilla display panel, designed for cleaner dashboards and improved readability in circuit network setups.

## Features

- Three new panel sizes:

  - 2x1 widescreen display panel
  - 3x1 widescreen display panel
  - 4x1 widescreen display panel

- Fully compatible with circuit networks

- Native-style rendering and behaviour

- Per-segment rule system with:

  - Multiple rules per segment
  - Signal-based conditions
  - Custom messages and icons
  - Optional alt-mode visibility
  - Optional chart tag display

- Copy and paste segment configurations between panels

## Integration

- Fully integrated with Display Signal Counts mod

## Usage

Each panel is divided into horizontal segments depending on its width. Each segment behaves as a single vanilla panel:

- Evaluates rules in order
- Displays the first matching rule
- Can show an icon and/or message
- Can optionally display in alt-mode
- Can optionally create a chart tag

### Wiring

- The **left side** of the panel functions as the circuit input
- The **right side** uses an invisible connector that outputs the merged signals

This allows panels to act as both display and passthrough components in circuit networks, and enables clean panel-chaining.

### Copy and Paste

Segments can be copied and pasted:

- Copy a configured segment
- Paste onto another segment or panel

## Unlocking

All widescreen panels are unlocked alongside the vanilla display panel via circuit network research.

## Notes

- Panels are fixed to north-facing orientation
- Behaviour is intentionally aligned with vanilla display panels where possible

## Compatibility

- Factorio 2.x
- Compatible with most mods that interact with display panels or circuit networks

## Known limitations

- No direct copy/paste from vanilla display panels
- Panels are fixed orientation (no flipping/rotating)

## Future plans

- Tallscreen panel variants
- Additional quality-of-life improvements

