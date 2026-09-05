# cl-history-kit

`cl-history-kit` is a **dependency-free command-history library for Common
Lisp**. It provides a capacity-bounded store of recorded input lines, four
search modes with smartcase, and the prefix-filtered recall cursor that an
Up/Down key pair drives.

Everything is portable Common Lisp with no runtime dependencies; only the test
system uses [cl-weave](https://github.com/nerima-lisp/cl-weave).

Start with [Getting Started](getting-started.md),
then move on to [Entries and the Store](guide/store.md), [Search](guide/search.md), and
[Recall Navigation](guide/navigation.md) for the full API surface.

<div class="grid cards" markdown>

-   :material-rocket-launch: **Get started**

    ---

    Install with Nix or ASDF and record your first entry in minutes.

    [:octicons-arrow-right-24: Getting Started](getting-started.md)

-   :material-book-open-variant: **Learn the API**

    ---

    The store, entries, search modes, and the recall cursor.

    [:octicons-arrow-right-24: Entries and the Store](guide/store.md)

-   :material-keyboard: **Wire up Up/Down**

    ---

    The frozen filter and the preserved origin.

    [:octicons-arrow-right-24: Recall Navigation](guide/navigation.md)

-   :material-format-list-bulleted: **Look something up**

    ---

    Every exported symbol with its signature and return values.

    [:octicons-arrow-right-24: API Reference](reference/api.md)

</div>

## Library guarantees

Interactive programs such as shells, REPLs, and multiplexers need a history
store and a cursor. This library defines the filtering and restoration rules
for that cursor.

### The filter is frozen when the walk begins

Type `git ` and press ++arrow-up++ to walk only entries starting with `git `.
The cursor keeps that filter while the buffer contains recalled commands.

### The in-progress input is preserved

Walking forward past the newest match restores the input that preceded the
walk.

```lisp
(history-kit:history-previous *history* "git ")  ; => "git commit -m wip"
(history-kit:history-next *history*)             ; => "git " -- restored
```

## Design notes

- **Immutable entries.** An entry's slots are read-only, its text is copied on
  construction, and it has no copier. The store only ever conses and drops whole
  entries.
- **An opaque store.** The store's slots sit behind a private conc-name and are
  reached through checked readers, so the navigation cursor's invariants cannot
  be broken from outside the library.
- **One definition of "matches".** Search and navigation funnel through the same
  four text predicates, so case sensitivity and smartcase cannot drift apart
  between them.
- **Automatic navigation reset.** Any operation that shifts entry positions
  ends an in-progress walk, rather than leaving a cursor pointing at a different
  entry than the user last saw.
