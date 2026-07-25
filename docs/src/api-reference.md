# API Reference

Every symbol below is exported from the `history-kit` package. Nothing else is
public; internal helpers carry a leading `%` and stay unexported.

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
| `duplicate-policy` | `:remove` or `:keep` | `:remove` | See [Entries and the Store](store.md#duplicate-policy) |

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

### `history-merge`

```lisp
(history-merge target source) → target
```

Merge `source` — a history or a newest-first list of entries — into `target`,
subject to `target`'s capacity and duplicate policy. Each entry keeps its
original timestamp and exit code. Signals `type-error` for any other `source`.

---

## Search

### `history-search`

```lisp
(history-search history query &key mode case-sensitive smartcase) → list of entry
```

| Parameter | Type | Default | Meaning |
| --- | --- | --- | --- |
| `query` | `string` | — | The text to match |
| `mode` | `:prefix`, `:exact`, `:contains`, `:line-prefix` | `:prefix` | See [Search](search.md#modes) |
| `smartcase` | boolean | `t` | Derive sensitivity from `query`; overrides `case-sensitive` |
| `case-sensitive` | boolean | `nil` | Used only when `smartcase` is `nil` |

Returns matching entries newest first, as a fresh list. An unknown `mode`
signals an `ecase` failure.

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
(history-previous history current-input) → string or nil
```

Step one match further back and return its text, or `nil` when there is no
older match (leaving the cursor where it was).

On the first call of a walk, `current-input` becomes both the filter for the
whole walk and the origin restored by `history-next`. Later calls ignore it.
Matching is line-prefix under smartcase.

### `history-next`

```lisp
(history-next history) → string or nil
```

Step one match toward the newest end. Stepping past the newest match ends the
walk and returns the preserved origin. Returns `nil` when no walk is in
progress.

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
| `history` | type | [Store](store.md) |
| `history-add` | function | [Store](store.md#recording) |
| `history-capacity` | function | [Store](store.md#reading-a-store) |
| `history-clear` | function | [Store](store.md#removing) |
| `history-count` | function | [Store](store.md#reading-a-store) |
| `history-delete` | function | [Store](store.md#removing) |
| `history-duplicate-policy` | function | [Store](store.md#reading-a-store) |
| `history-empty-p` | function | [Store](store.md#reading-a-store) |
| `history-entries` | function | [Store](store.md#reading-a-store) |
| `history-entry` | type | [Store](store.md#entries) |
| `history-entry-exit-code` | function | [Store](store.md#entries) |
| `history-entry-line-suffix` | function | [Search](search.md#autosuggestion) |
| `history-entry-match-p` | function | [Search](search.md#matching-a-single-entry) |
| `history-entry-p` | function | [Store](store.md#entries) |
| `history-entry-text` | function | [Store](store.md#entries) |
| `history-entry-texts` | function | [Store](store.md#entries) |
| `history-entry-timestamp` | function | [Store](store.md#entries) |
| `history-merge` | function | [Store](store.md#merging) |
| `history-navigating-p` | function | [Navigation](navigation.md#ending-a-walk) |
| `history-next` | function | [Navigation](navigation.md#walking-forward) |
| `history-p` | function | [Store](store.md) |
| `history-previous` | function | [Navigation](navigation.md#walking-backward) |
| `history-reset-navigation` | function | [Navigation](navigation.md#ending-a-walk) |
| `history-search` | function | [Search](search.md) |
| `make-history` | function | [Store](store.md#creating-a-store) |
| `make-history-entry` | function | [Store](store.md#entries) |
