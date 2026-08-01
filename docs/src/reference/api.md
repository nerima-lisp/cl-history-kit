# API Reference

Every symbol below is exported from the `history-kit` package. Nothing else is
public; internal helpers carry a leading `%` and stay unexported. This surface
is frozen for the 1.x series — see [Stability](../project/scope.md#stability).

Parameters listed as `boolean` below are *generalized* booleans in the Common
Lisp sense: any non-`nil` value counts as true.

## Types

### `history-entry`

Structure type. One recorded line of history, immutable: all slots read-only,
no copier.

### `history`

Structure type. A bounded store of entries plus a transient navigation cursor.
Its slots are private; use the readers below.

---

## Entries

### `make-history-entry`

```lisp
(make-history-entry text &key timestamp exit-code) → entry
```

Create an entry recording `text`.

| Parameter | Type | Default | Meaning |
| --- | --- | --- | --- |
| `text` | `string` | — | The recorded input; copied |
| `timestamp` | `integer` | now | Universal time |
| `exit-code` | `integer` or `nil` | `nil` | Exit status of the command |

Signals `type-error` on a wrong-typed argument.

### `history-entry-p`

```lisp
(history-entry-p object) → boolean
```

### `history-entry-text`

```lisp
(history-entry-text entry) → string
```

Returns a fresh string. Mutating that result cannot change the entry stored in
the history.

### `history-entry-timestamp`

```lisp
(history-entry-timestamp entry) → integer
```

The universal time at which the entry was recorded.

### `history-entry-exit-code`

```lisp
(history-entry-exit-code entry) → integer or nil
```

### `history-entry-texts`

```lisp
(history-entry-texts entries) → list of string
```

The recorded text of each entry in `entries`, in order.

---

## Store

### `make-history`

```lisp
(make-history &key capacity duplicate-policy) → history
```

| Parameter | Type | Default | Meaning |
| --- | --- | --- | --- |
| `capacity` | `(integer 0 *)` | `10000` | Maximum entries retained |
| `duplicate-policy` | `:remove` or `:keep` | `:remove` | See [Entries and the Store](../guide/store.md#duplicate-policy) |

### `history-p`

```lisp
(history-p object) → boolean
```

### `history-entries`

```lisp
(history-entries history) → list of entry
```

The stored entries, newest first, as a **fresh** list. The entries themselves
are shared, which is safe because they are immutable.

The store keeps its bounded state in an internal ring; this accessor
materializes the public snapshot. Use search and navigation APIs for hot read
paths instead of repeatedly requesting snapshots.

### `history-count`

```lisp
(history-count history) → integer
```

### `history-capacity`

```lisp
(history-capacity history) → integer
```

### `history-empty-p`

```lisp
(history-empty-p history) → boolean
```

### `history-duplicate-policy`

```lisp
(history-duplicate-policy history) → :remove or :keep
```

---

## Operations

### `history-add`

```lisp
(history-add history text &key exit-code timestamp) → history, entry
```

Record `text` as the newest entry. Honours the duplicate policy, evicts past
capacity, and **resets navigation**. Returns two values: the store and the
entry just recorded.

With `:keep`, recording into a full history overwrites the oldest physical
slot, so insertion remains constant time. Under `:remove`, an internal text
index makes a new command constant time; only an existing command triggers a
scan and in-place compaction of the retained ring buffer. That duplicate path
takes O(n), but never allocates a public entry-list snapshot.

### `history-clear`

```lisp
(history-clear history) → history
```

Remove every entry and reset navigation.

### `history-delete`

```lisp
(history-delete history text &key case-sensitive) → integer
```

Delete every entry whose text equals `text`. `case-sensitive` defaults to
**true** (unlike search, which uses smartcase). Returns the number deleted;
navigation resets only when that count is non-zero.

### `history-delete-if`

```lisp
(history-delete-if history predicate) → integer
```

Delete every entry for which `predicate`, called with the `history-entry`
object itself rather than merely its text, returns true -- for example purging
failed commands via `history-entry-exit-code`, or everything older than some
universal time via `history-entry-timestamp`. The predicate-based counterpart
to `history-delete`, which only matches by exact text. Returns the number
deleted; navigation resets only when that count is non-zero.

### `history-dedup`

```lisp
(history-dedup history) → integer
```

Compact `history` in place, keeping each distinct text's newest occurrence and
removing the rest, under the same case-sensitive comparison `history-add` uses
at add-time under the `:remove` duplicate policy. Works regardless of
`history`'s `:duplicate-policy` -- that policy only governs what `history-add`
does going forward, whereas this is an explicit, on-demand purge of whatever is
currently stored. Returns the number of entries removed; navigation resets only
when that count is non-zero.

### `history-merge`

```lisp
(history-merge target source) → target
```

Merge `source` — a history or a newest-first list of entries — into `target`,
subject to `target`'s capacity and duplicate policy. Each entry keeps its
original timestamp and exit code. A capacity-safe `:keep` merge writes entries
directly into the target ring; other merges first compute a bounded result so
validation and duplicate removal remain atomic. Signals `type-error` for any
other `source`.

---

## Search

### `history-search`

```lisp
(history-search history query &key mode case-sensitive smartcase limit) → list of entry
```

| Parameter | Type | Default | Meaning |
| --- | --- | --- | --- |
| `query` | `string` | — | The text to match |
| `mode` | `:prefix`, `:exact`, `:contains`, `:line-prefix` | `:prefix` | See [Search](../guide/search.md#modes) |
| `smartcase` | boolean | `t` | Derive sensitivity from `query`; overrides `case-sensitive` |
| `case-sensitive` | boolean | `nil` | Used only when `smartcase` is `nil` |
| `limit` | `(integer 0 *)` or `nil` | `nil` | Cap the result to at most this many of the newest matches |

Returns matching entries newest first, as a fresh list, truncated to `limit`
entries when `limit` is non-`nil`. An unknown `mode` signals an `ecase`
failure; a non-`nil` `limit` outside `(integer 0 *)` signals `type-error`.

### `history-entry-match-p`

```lisp
(history-entry-match-p entry query &key mode case-sensitive) → boolean
```

The same four modes applied to one entry. No `smartcase` option: this is the
primitive, so the caller decides sensitivity outright.

### `history-entry-line-suffix`

```lisp
(history-entry-line-suffix entry query &key case-sensitive) → string or nil
```

The remainder of the first line of `entry` beginning with `query` — the text an
autosuggestion would append. Returns `nil` when no line matched and `""` when a
line is exactly `query`; the two are deliberately distinguishable.

---

## Navigation

### `history-previous`

```lisp
(history-previous history current-input &key mode wrap case-sensitive smartcase) → string or nil
```

| Parameter | Type | Default | Meaning |
| --- | --- | --- | --- |
| `current-input` | `string` | — | The buffer; becomes the walk's filter and origin on the first call |
| `mode` | `:prefix`, `:exact`, `:contains`, `:line-prefix` | `:line-prefix` | The walk's match mode, one of `history-search`'s four |
| `wrap` | boolean | `nil` | Whether either end of the walk cycles to the other instead of stopping there |
| `smartcase` | boolean | `t` | Derive sensitivity from `current-input`; overrides `case-sensitive` |
| `case-sensitive` | boolean | `nil` | Used only when `smartcase` is `nil` |

Step one match further back and return its text, or `nil` when there is no
older match (leaving the cursor where it was) -- unless `wrap` was frozen `t`
for this walk and at least one match exists anywhere in `history`, in which
case it wraps around to the newest match instead of returning `nil`.

On the first call of a walk, `current-input` becomes both the filter for the
whole walk and the origin restored by `history-next`, `mode` becomes the
walk's match mode, `wrap` decides whether either end cycles to the other
instead of ending the walk, and case sensitivity is decided exactly as
`history-search` decides it, from `smartcase`/`case-sensitive`. Later calls
ignore all four keyword arguments, along with `current-input` itself. An
unknown `mode` signals the same `ecase` failure as `history-search`.

### `history-next`

```lisp
(history-next history) → string or nil
```

Step one match toward the newest end. Stepping past the newest match ends the
walk and returns the preserved origin -- unless `wrap` was frozen `t` when the
walk began (see `history-previous`), in which case it wraps around to the
oldest match and continues instead. Returns `nil` when no walk is in progress.

### `history-navigating-p`

```lisp
(history-navigating-p history) → boolean
```

### `history-reset-navigation`

```lisp
(history-reset-navigation history) → history
```

Abandon any active walk.

---

## Symbol index

| Symbol | Kind | Page |
| --- | --- | --- |
| `history` | type | [Store](../guide/store.md) |
| `history-add` | function | [Store](../guide/store.md#recording) |
| `history-capacity` | function | [Store](../guide/store.md#reading-a-store) |
| `history-clear` | function | [Store](../guide/store.md#removing) |
| `history-count` | function | [Store](../guide/store.md#reading-a-store) |
| `history-dedup` | function | [Store](../guide/store.md#removing) |
| `history-delete` | function | [Store](../guide/store.md#removing) |
| `history-delete-if` | function | [Store](../guide/store.md#removing) |
| `history-duplicate-policy` | function | [Store](../guide/store.md#reading-a-store) |
| `history-empty-p` | function | [Store](../guide/store.md#reading-a-store) |
| `history-entries` | function | [Store](../guide/store.md#reading-a-store) |
| `history-entry` | type | [Store](../guide/store.md#entries) |
| `history-entry-exit-code` | function | [Store](../guide/store.md#entries) |
| `history-entry-line-suffix` | function | [Search](../guide/search.md#autosuggestion) |
| `history-entry-match-p` | function | [Search](../guide/search.md#matching-a-single-entry) |
| `history-entry-p` | function | [Store](../guide/store.md#entries) |
| `history-entry-text` | function | [Store](../guide/store.md#entries) |
| `history-entry-texts` | function | [Store](../guide/store.md#entries) |
| `history-entry-timestamp` | function | [Store](../guide/store.md#entries) |
| `history-merge` | function | [Store](../guide/store.md#merging) |
| `history-navigating-p` | function | [Navigation](../guide/navigation.md#ending-a-walk) |
| `history-next` | function | [Navigation](../guide/navigation.md#walking-forward) |
| `history-p` | function | [Store](../guide/store.md) |
| `history-previous` | function | [Navigation](../guide/navigation.md#walking-backward) |
| `history-reset-navigation` | function | [Navigation](../guide/navigation.md#ending-a-walk) |
| `history-search` | function | [Search](../guide/search.md) |
| `make-history` | function | [Store](../guide/store.md#creating-a-store) |
| `make-history-entry` | function | [Store](../guide/store.md#entries) |
