# signal

## 1.5.0

### Minor Changes

- 0836bdf: Add a Preferences option to hide Signal's menu bar icon. While it's hidden, opening Signal again from Spotlight or Finder brings up Preferences so you can turn it back on
- 91f478a: Reorder tasks with the keyboard: Option+Up / Option+Down move the focused task
- 960f0e7: Point out where Signal lives in the menu bar with a one-time "Signal lives here!" hint after onboarding
- 609e1d7: Choose which output device plays each of Signal's sound cues (on open, on completion, on all done) in Preferences, so the auto-open chime can go to the built-in speakers even while headphones are the system default
- c27eb25: Show tasks that arrive from your schedule in their own SCHEDULED section at the bottom of the panel, so recurring and planned-ahead tasks never take one of the three Signal slots
- 999d96f: Manage tasks straight from the Scheduled view: add, edit and remove them on today and on any day ahead, with the same rows, keyboard and delete button as the main Signal panel. Typing a keyword like "every monday" on a day schedules it there, so the frequency popover is gone; days already past stay read-only history

### Patch Changes

- dcbfaa4: Wrap long tasks onto up to three lines instead of scrolling them sideways, so the text stays aligned with the other rows. Past three lines the row scrolls its own text, and the arrow keys walk those lines before moving to the next task
- 65dd2fb: Update the keyboard shortcut hints in the menu bar menu immediately after changing a hotkey in Preferences, instead of only after relaunching Signal
- 9a5e21d: Skip the daily prompt and quick glances when Signal is already open or when every task for the day is already done
- 444062a: Scroll the task list while a task is dragged or moved with Option+Up / Option+Down to the edge of the panel, so long lists can be reordered without losing sight of the row

## 1.4.0

### Minor Changes

- 930b209: Improvements to the task writing experience: arrow navigation, backspace to delete, enter to toggle
- 9e747a3: Remove max limit of tasks, style the first three differently, and add ability to reorder

### Patch Changes

- aaf95cf: Fix open sound not triggering on automatic opens
- 9790982: Allow to close Signal UI if mouse is hovering

## 1.3.0

### Minor Changes

- a1805fb: Add What's New window after installing a new update
- a6ad0d3: Add natural language scheduling of tasks
- 1a452d7: Long press hotkey to open a new UI to view all scheduled tasks

### Patch Changes

- 92c3e90: Show shortcuts in menu bar items
- 7d56c8a: Fix automatic updates failing to install

## 1.2.0

### Minor Changes

- 599d50f: Prompt for App Store review after completing the day for the first time
- 756064b: Add Task Stats view with a new hotkey to view statistics

### Patch Changes

- e621a6d: Fix Preferences window not coming to foreground when opening

## 1.1.0

### Minor Changes

- 901e7c0: Add automatic updates for direct-download installs.

## 1.0.2

### Patch Changes

- c72b52b: Add About Tab to Preferences window

## 1.0.1

### Patch Changes

- 681534b: Fix missing app icon in distributed builds
