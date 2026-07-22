# Ranking — Wilson lower-bound confidence score

Write me an Elixir module called `Ranking` that scores and ranks content items
(posts, links, comments) by the **lower bound of the Wilson score confidence
interval** for the proportion of upvotes. This is the "best" ranking used to
sort comments by quality: it rewards a high upvote ratio, but penalizes small
sample sizes so a single lucky upvote can't beat a well-established item.

Use only the Elixir/Erlang standard library — no external dependencies. Put
everything in a single module.

## The item shape

Each item is a plain map with atom keys:

- `:upvotes` — non-negative integer
- `:downvotes` — non-negative integer

Items may carry additional keys (e.g. an `:id`); ignore anything you don't
need, and `rank/2` must return the item maps **unchanged**.

## Public API

### `Ranking.score(item, opts \\ [])` → float

Computes the Wilson lower bound as a float.

Let `n = upvotes + downvotes`. If `n == 0`, the score is `0.0` (and it must
never raise). Otherwise, with `p = upvotes / n`:

```
z2          = z * z
denominator = 1 + z2 / n
center      = p + z2 / (2 * n)
margin      = z * sqrt( (p * (1 - p) + z2 / (4 * n)) / n )
score       = (center - margin) / denominator
```

Supported options (all optional):

- `:z` — the z-score for the desired confidence level. Defaults to `1.96`
  (≈ 95% confidence). A larger `z` widens the interval and therefore **lowers**
  the score for the same item.

Notes:

- With `n == 0` the result is exactly `0.0`.
- More votes at the same ratio raise the score (the interval tightens upward):
  10 up / 0 down scores higher than 1 up / 0 down.
- A large, well-supported item with a slightly lower ratio can outrank a tiny
  item with a perfect ratio (proven quality beats uncertain perfection).

### `Ranking.rank(items, opts \\ [])` → list of items

Returns the items sorted by score **descending** (highest first), threading the
same `opts` through to the scoring.

Tie-breaking rules, applied in order:

1. Higher score first.
2. If scores are equal, the item with more total votes (`upvotes + downvotes`)
   comes first.
3. If both are equal, preserve the items' original relative order (stable sort).

`rank/2` must handle the empty list and a single-item list gracefully.

## Behavioral expectations

- An item with no votes scores `0.0` and never raises.
- Adding a downvote lowers an item's score.
- More total votes at the same ratio produce a higher (more confident) score.
- A higher `:z` (more confidence demanded) lowers every non-empty score.

Give me the complete `Ranking` module in a single file.