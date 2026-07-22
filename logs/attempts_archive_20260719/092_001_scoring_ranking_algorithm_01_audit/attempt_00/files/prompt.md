# Ranking — a configurable "hot score" for content

Write me an Elixir module called `Ranking` that scores and ranks content items
(think posts, links, or comments) using a configurable "hot score" formula that
blends **recency**, **net votes**, and **engagement**.

Use only the Elixir/Erlang standard library — no external dependencies. Put
everything in a single module.

## The item shape

Each item is a plain map with atom keys:

- `:upvotes` — non-negative integer
- `:downvotes` — non-negative integer
- `:created_at` — an integer Unix timestamp in **seconds**
- `:view_count` — non-negative integer
- `:comment_count` — non-negative integer

Items may carry additional keys (e.g. an `:id`); your code must ignore anything
it doesn't need, and `rank/2` must return the item maps **unchanged**.

## Public API

### `Ranking.score(item, opts \\ [])` → float

Computes the hot score of a single item as a float.

Supported options (all optional):

- `:now` — integer Unix timestamp in seconds used as the current-time reference.
  Defaults to `System.os_time(:second)`.
- `:half_life_hours` — a positive number controlling how fast recency decays.
  Defaults to `12`.
- `:weights` — a map that is **merged over** the defaults
  `%{votes: 1.0, recency: 1.0, engagement: 1.0}`, so callers can override any
  subset of the three weights.

Compute the score with exactly this formula:

```
net_votes = upvotes - downvotes                         # may be negative

age_hours = max(now - created_at, 0) / 3600             # clamp: never negative
recency   = 2 ** (-age_hours / half_life_hours)         # 1.0 at age 0, 0.5 at one half-life

engagement = if view_count > 0, do: comment_count / view_count, else: 0.0

score = weights.votes      * net_votes
      + weights.recency     * recency
      + weights.engagement  * engagement
```

Notes:

- `recency` is `1.0` when the item was just created and decays toward `0` as it
  ages; an item whose age equals `half_life_hours` has `recency = 0.5`.
- An item created in the "future" relative to `:now` is treated as age `0`
  (recency `1.0`), never more.
- `engagement` is the comment/view ratio; a `:view_count` of `0` yields `0.0`
  and must never raise.

### `Ranking.rank(items, opts \\ [])` → list of items

Returns the items sorted by score **descending** (highest score first). Pass the
same `opts` through to the scoring so a caller can rank under custom weights,
`:now`, or `:half_life_hours`.

Tie-breaking rules, applied in order:

1. Higher score first.
2. If scores are equal, the more recently created item (larger `:created_at`)
   comes first.
3. If both score and `:created_at` are equal, preserve the items' original
   relative order (stable sort).

`rank/2` must handle the empty list and a single-item list gracefully.

## Behavioral expectations

- Given equal net votes, a **recent** item ranks above an **older** one.
- Given equal age, a **highly-upvoted** item ranks above one with few votes.
- Heavily downvoted items (negative net votes) sink toward the bottom.
- Cranking the `:recency` weight up (or `:votes` down) can let a fresh, modestly
  upvoted item overtake a stale, highly upvoted one — the formula is genuinely
  configurable.

Give me the complete `Ranking` module in a single file.