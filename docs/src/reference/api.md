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
(make-history-entry text &key timestamp exit-code cwd duration-ms origin session) → entry
```

Create an entry recording `text`.

| Parameter | Type | Default | Meaning |
| --- | --- | --- | --- |
| `text` | `string` | — | The recorded input; copied |
| `timestamp` | `integer` | now | Universal time |
| `exit-code` | `integer` or `nil` | `nil` | Exit status of the command |
| `cwd` | `string` or `nil` | `nil` | Working directory the command ran in; copied |
| `duration-ms` | `(integer 0 *)` or `nil` | `nil` | Run time in milliseconds |
| `origin` | `symbol` or `nil` | `nil` | Where the text came from, such as `:typed` or `:agent`; any symbol is stored as-is |
| `session` | `string` or `nil` | `nil` | Host-defined session identifier; copied |

Signals `type-error` on a wrong-typed argument. See
[Entry metadata](../guide/store.md#entry-metadata) for how a host can use the
optional slots.

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

### `history-entry-cwd`

```lisp
(history-entry-cwd entry) → string or nil
```

Returns a fresh string, like `history-entry-text`.

### `history-entry-duration-ms`

```lisp
(history-entry-duration-ms entry) → (integer 0 *) or nil
```

The command's run time in milliseconds.

### `history-entry-origin`

```lisp
(history-entry-origin entry) → symbol or nil
```

The symbol recorded as the entry's origin. The library does not restrict it to
a known set, so a record written by a newer host keeps its origin; deciding how
to treat an unfamiliar origin is host policy.

### `history-entry-session`

```lisp
(history-entry-session entry) → string or nil
```

Returns a fresh string, or `nil` when no session was recorded.

### `history-entry-plist`

```lisp
(history-entry-plist entry) → plist
```

A fresh property list describing `entry`:
`(:text … :timestamp … [:exit-code …] [:cwd …] [:duration-ms …] [:origin …] [:session …])`.
`:text` and `:timestamp` are always present; each optional key appears only
when its value is non-`nil`. The result contains only strings, integers, and
symbols, so it prints readably. See
[Serializing entries](../guide/store.md#serializing-entries).

### `history-entry-from-plist`

```lisp
(history-entry-from-plist plist) → entry
```

The inverse of `history-entry-plist`. `:text` is required. `:timestamp`
defaults to `0` and is never restamped with the current time. Every metadata
key is optional, so a record written before a host stored metadata reads back
with `nil` metadata. Unknown keys are ignored, and an unknown `:origin` symbol
is kept. Signals `type-error` when `plist` is not a list, `:text` is missing,
or a value has the wrong type, and `simple-error` when `plist` has odd length
or is circular.

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
materializes the public snapshot. Use `history-entry-at`, `map-history`, or the
search and navigation APIs for hot read paths instead of repeatedly requesting
snapshots.

### `history-entry-at`

```lisp
(history-entry-at history index) → entry or nil
```

The entry at newest-first position `index`, where `0` is the newest entry.
Returns `nil` when `index` is at or past `history-count`. Does not allocate.

### `history-newest`

```lisp
(history-newest history) → entry or nil
```

The newest entry, or `nil` for an empty history.

### `map-history`

```lisp
(map-history function history &key filter limit) → nil
```

| Parameter | Type | Default | Meaning |
| --- | --- | --- | --- |
| `function` | function of one entry | — | Called once per visited entry |
| `filter` | function of one entry, or `nil` | `nil` | Entries for which it returns false are skipped and not passed to `function` |
| `limit` | `(integer 0 *)` or `nil` | `nil` | Stop after `function` has been called this many times |

Call `function` on each entry, newest first, without building a list. Returns
`nil`. A non-local exit from `function` (`return-from`, `throw`) ends the walk
early. Mutating `history` during the walk signals a `simple-error`: the
revision is compared before each entry is read and again after the last one.

`history-entries` conses a fresh list of every entry on each call; prefer
`map-history` for work that runs on every keystroke.

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
(history-add history text &key exit-code timestamp cwd duration-ms origin session) → history, entry
```

Record `text` as the newest entry. The keyword arguments are passed to
`make-history-entry`. Honours the duplicate policy, evicts past capacity, and
**resets navigation**. Returns two values: the store and the entry just
recorded.

Under `:remove`, re-recording a stored text replaces the older entry together
with its metadata: the new entry's `cwd`, `origin`, and other slots win.

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
original timestamp, exit code, and metadata. A capacity-safe `:keep` merge writes entries
directly into the target ring; other merges first compute a bounded result so
validation and duplicate removal remain atomic. Signals `type-error` for any
other `source`.

---

## Search

### `history-search`

```lisp
(history-search history query &key mode case-sensitive smartcase limit filter) → list of entry
```

| Parameter | Type | Default | Meaning |
| --- | --- | --- | --- |
| `query` | `string` | — | The text to match |
| `mode` | `:prefix`, `:exact`, `:contains`, `:line-prefix`, `:fuzzy` | `:prefix` | See [Search](../guide/search.md#modes) |
| `smartcase` | boolean | `t` | Derive sensitivity from `query`; overrides `case-sensitive` |
| `case-sensitive` | boolean | `nil` | Used only when `smartcase` is `nil` |
| `limit` | `(integer 0 *)` or `nil` | `nil` | Cap the result to at most this many of the newest matches |
| `filter` | function of one entry, or `nil` | `nil` | Entries for which it returns false are excluded, in addition to `mode` |

Returns matching entries newest first, as a fresh list, truncated to `limit`
entries when `limit` is non-`nil`. Entries rejected by `filter` do not count
toward `limit`. `:fuzzy` keeps newest-first order here; use
`history-fuzzy-search` for results ranked by score. An unknown `mode` signals an `ecase`
failure; a non-`nil` `limit` outside `(integer 0 *)` signals `type-error`.

### `history-entry-match-p`

```lisp
(history-entry-match-p entry query &key mode case-sensitive) → boolean
```

The same modes as `history-search`, including `:fuzzy`, applied to one entry. No `smartcase` option: this is the
primitive, so the caller decides sensitivity outright.

### `history-entry-fuzzy-score`

```lisp
(history-entry-fuzzy-score entry query &key case-sensitive) → integer or nil
```

Score `entry` against `query` as a subsequence match: every character of
`query` must appear in the entry text in order. Returns `nil` when it does not.
Otherwise returns an integer where higher is better: consecutive matched
characters and matches at a word boundary (the start of the text, or after a
space, `/`, `-`, `_`, `.`, or newline) raise the score, and gaps between matched
characters lower it. The score comes from a greedy single pass, not an optimal
alignment, and its exact values are not part of the API; compare scores only
with each other.

### `history-fuzzy-search`

```lisp
(history-fuzzy-search history query &key filter limit case-sensitive smartcase) → list of entry
```

| Parameter | Type | Default | Meaning |
| --- | --- | --- | --- |
| `query` | `string` | — | Characters that must appear in order |
| `filter` | function of one entry, or `nil` | `nil` | Entries for which it returns false are excluded |
| `limit` | `(integer 0 *)` or `nil` | `nil` | Keep only the top `limit` entries after ranking |
| `smartcase` | boolean | `t` | Derive sensitivity from `query`; overrides `case-sensitive` |
| `case-sensitive` | boolean | `nil` | Used only when `smartcase` is `nil` |

Returns the entries that `:fuzzy` matches as a fresh list, ranked by
`history-entry-fuzzy-score`, highest first. Entries with equal scores stay
newest first. Intended for a ++ctrl+r++ picker. See
[Fuzzy search](../guide/search.md#fuzzy-search).

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
| `mode` | `:prefix`, `:exact`, `:contains`, `:line-prefix`, `:fuzzy` | `:line-prefix` | The walk's match mode, any of `history-search`'s modes |
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
| `history-entry-at` | function | [Store](../guide/store.md#allocation-free-access) |
| `history-entry-cwd` | function | [Store](../guide/store.md#entry-metadata) |
| `history-entry-duration-ms` | function | [Store](../guide/store.md#entry-metadata) |
| `history-entry-exit-code` | function | [Store](../guide/store.md#entries) |
| `history-entry-from-plist` | function | [Store](../guide/store.md#serializing-entries) |
| `history-entry-fuzzy-score` | function | [Search](../guide/search.md#fuzzy-search) |
| `history-entry-line-suffix` | function | [Search](../guide/search.md#autosuggestion) |
| `history-entry-match-p` | function | [Search](../guide/search.md#matching-a-single-entry) |
| `history-entry-origin` | function | [Store](../guide/store.md#entry-metadata) |
| `history-entry-p` | function | [Store](../guide/store.md#entries) |
| `history-entry-plist` | function | [Store](../guide/store.md#serializing-entries) |
| `history-entry-session` | function | [Store](../guide/store.md#entry-metadata) |
| `history-entry-text` | function | [Store](../guide/store.md#entries) |
| `history-entry-texts` | function | [Store](../guide/store.md#entries) |
| `history-entry-timestamp` | function | [Store](../guide/store.md#entries) |
| `history-fuzzy-search` | function | [Search](../guide/search.md#fuzzy-search) |
| `history-merge` | function | [Store](../guide/store.md#merging) |
| `history-navigating-p` | function | [Navigation](../guide/navigation.md#ending-a-walk) |
| `history-newest` | function | [Store](../guide/store.md#allocation-free-access) |
| `history-next` | function | [Navigation](../guide/navigation.md#walking-forward) |
| `history-p` | function | [Store](../guide/store.md) |
| `history-previous` | function | [Navigation](../guide/navigation.md#walking-backward) |
| `history-reset-navigation` | function | [Navigation](../guide/navigation.md#ending-a-walk) |
| `history-search` | function | [Search](../guide/search.md) |
| `make-history` | function | [Store](../guide/store.md#creating-a-store) |
| `make-history-entry` | function | [Store](../guide/store.md#entries) |
| `map-history` | function | [Store](../guide/store.md#allocation-free-access) |
