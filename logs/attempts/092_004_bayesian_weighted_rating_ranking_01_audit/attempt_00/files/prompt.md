# Ranking — Bayesian weighted-rating ("IMDb Top 250") score

Write me an Elixir module called `Ranking` that scores and ranks rated content
items (movies, products, restaurants) using a **Bayesian weighted rating** —
the formula behind the IMDb Top 250. The trick is that a rating is pulled toward
the corpus-wide mean in proportion to how few votes it has, so a 9.5-star item
with 3 votes doesn't automatically beat an 8.9-star item with 100,000 votes.

Use only the Elixir/Erlang standard library — no external dependencies. Put
everything in a single module.

## The item shape

Each item is a plain map with atom keys:

- `:rating` — the item's own average rating, a number (e.g. on a 0–10 scale)
- `:vote_count` — non-negative integer, the number of ratings the item received

Items may carry additional keys (e.g. an `:id`); ignore anything you don't
need, and `rank/2` must return the item maps **unchanged**.

## Public API

### `Ranking.score(item, opts \\ [])` → float

Computes the weighted rating as a float, using exactly this formula:

```
v = vote_count
R = rating
m = min_votes            # the "smoothing" prior weight
C = mean                 # the prior mean the rating is pulled toward

score = (v / (v + m)) * R + (m / (v + m)) * C
```

Supported options (all optional):

- `:min_votes` — the prior weight `m`, a non-negative number. Defaults to `25`.
  A larger `m` pulls low-vote items more strongly toward the mean.
- `:mean` — the prior mean `C`. Defaults to `0.0`.

Notes:

- If `v + m == 0` (only possible when both `vote_count` and `:min_votes` are 0),
  return `C`. The function must never raise or divide by zero.
- An item with `vote_count == 0` scores exactly `C` — with no evidence, its
  score is the prior mean.
- An item whose `rating` equals `C` scores exactly `C` regardless of vote count.

### `Ranking.rank(items, opts \\ [])` → list of items

Returns the items sorted by score **descending** (highest first).

Crucially, `rank/2` is **corpus-aware**: if `opts` does **not** contain `:mean`,
compute `C` as the arithmetic mean of the `:rating` values across the items
being ranked (`0.0` for an empty list), and use that `C` when scoring every
item. If `opts` **does** contain `:mean`, use the provided value verbatim.
`:min_votes` is threaded through unchanged.

Tie-breaking rules, applied in order:

1. Higher score first.
2. If scores are equal, the item with more `:vote_count` comes first.
3. If both are equal, preserve the items' original relative order (stable sort).

`rank/2` must handle the empty list and a single-item list gracefully.

## Behavioral expectations

- A high rating backed by very few votes is dragged toward the mean and can be
  overtaken by a slightly lower rating with many votes.
- A large `:min_votes` pulls low-vote items more strongly toward the mean.
- An item with no votes ranks exactly at the corpus mean.

Give me the complete `Ranking` module in a single file.