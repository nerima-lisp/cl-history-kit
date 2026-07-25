# cl-history-kit

`cl-history-kit` is a **dependency-free command-history library for Common
Lisp**. It provides a capacity-bounded store of recorded input lines, four
search modes with smartcase, and the prefix-filtered recall cursor that an
Up/Down key pair drives.

Everything is portable Common Lisp with no runtime dependencies; only the test
system uses [cl-weave](https://github.com/nerima-lisp/cl-weave).

Start with [Installation](installation.md) and [Quick Start](quick-start.md),
then move on to [Entries and the Store](store.md), [Search](search.md), and
[Recall Navigation](navigation.md) for the full API surface.

<div class="grid cards" markdown>

-   :material-rocket-launch: **Get started**

    ---

    Install with Nix or ASDF and record your first entry in minutes.

    [:octicons-arrow-right-24: Installation](installation.md)

-   :material-book-open-variant: **Learn the API**

    ---

    The store, entries, search modes, and the recall cursor.

    [:octicons-arrow-right-24: Entries and the Store](store.md)

-   :material-keyboard: **Wire up Up/Down**

    ---

    The frozen filter and the preserved origin, and why they matter.

    [:octicons-arrow-right-24: Recall Navigation](navigation.md)

-   :material-format-list-bulleted: **Look something up**

    ---

    Every exported symbol with its signature and return values.

    [:octicons-arrow-right-24: API Reference](api-reference.md)

</div>

## Why a library for this?

Every interactive program eventually grows a history: a shell, a REPL, a
multiplexer's command prompt. The list-with-a-cursor looks trivial, so it gets
rewritten each time — and each rewrite loses a different detail. Two of them
matter enough to be the reason this library exists.

### The filter is frozen when the walk begins

Type `git ` and press ++arrow-up++ and you walk only the entries starting with
`git `. Press it again and you keep walking those, even though the buffer now
shows a recalled command that no longer resembles the original prefix. A
cursor that re-derives its filter from the current buffer would jump to a
different set of entries on the second press.

### The in-progress input is preserved

Walking forward past the newest match hands back exactly what you had typed,
not an empty buffer. An accidental ++arrow-up++ is therefore free to undo — the
half-written command is still there.

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
