# tratrack macOS app

SwiftUI app (Swift Package, macOS 14+) that draws a workflow JSON as a route of sticky notes, one note per task.

```bash
swift run
```

Or open a workflow directly:

```bash
swift run TratrackApp ../examples/bogota.json
```

- **Top bar:** "Load MP4" button, a search field, and a Run button.
- **Actions menu:** "Load Video…" (⇧⌘O) and "Load JSON…" (⌘O). You can also drop a `.json` or `.mp4` file onto the window.
- **Canvas:** reads two layouts. In `examples/bogota.json`, `tasks` is an array drawn in file order. In `examples/october.json` and `examples/pizza.json`, `tasks` is keyed by name and ordered by following each task's first link from `initial`; those notes show the next task instead of a summary. The title is the workflow's `name` (or the file name). Each task is a note showing its `summary`, `time_field`, `amount_field` and video count. A `transition.wrapped` day total is drawn after the last task of that day.

Run is not connected to the service yet; it only reports what it would send.
