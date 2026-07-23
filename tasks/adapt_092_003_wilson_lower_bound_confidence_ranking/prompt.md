# Rework this solution for a changed brief

The module below is a complete, tested solution to a neighboring task. Treat
it as your starting codebase, not as a suggestion — carry over what still
fits and rewrite what the new brief demands. Where old code and the new
specification conflict (module name, public API, behavior, constraints,
output format), the new specification is authoritative. Return the complete
final result.

## Existing code (your starting point)

```elixir
defmodule Ranking do
  @moduledoc """
  A configurable "hot score" ranking for content items.

  Each item is a plain map with atom keys:

    * `:upvotes` — non-negative integer
    * `:downvotes` — non-negative integer
    * `:created_at` — integer Unix timestamp in seconds
    * `:view_count` — non-negative integer
    * `:comment_count` — non-negative integer

  Items may carry any number of additional keys (such as an `:id`); those are
  ignored and items are never mutated.

  The hot score blends three components — net votes, recency, and engagement —
  each with a configurable weight:

      net_votes  = upvotes - downvotes
      age_hours  = max(now - created_at, 0) / 3600
      recency    = 2 ** (-age_hours / half_life_hours)
      engagement = if view_count > 0, do: comment_count / view_count, else: 0.0

      score = weights.votes      * net_votes
            + weights.recency     * recency
            + weights.engagement  * engagement
  """

  @default_weights %{votes: 1.0, recency: 1.0, engagement: 1.0}
  @default_half_life_hours 12
  @seconds_per_hour 3600

  @doc """
  Computes the hot score of a single `item` as a float.

  ## Options

    * `:now` — integer Unix timestamp in seconds used as the current-time
      reference. Defaults to `System.os_time(:second)`.
    * `:half_life_hours` — a positive number controlling how fast recency
      decays. Defaults to `12`.
    * `:weights` — a map merged over the defaults
      `%{votes: 1.0, recency: 1.0, engagement: 1.0}`.
  """
  @spec score(map(), keyword()) :: float()
  def score(item, opts \\ []) when is_map(item) and is_list(opts) do
    now = Keyword.get(opts, :now, System.os_time(:second))
    half_life_hours = Keyword.get(opts, :half_life_hours, @default_half_life_hours)
    weights = Map.merge(@default_weights, Keyword.get(opts, :weights, %{}))

    upvotes = Map.fetch!(item, :upvotes)
    downvotes = Map.fetch!(item, :downvotes)
    created_at = Map.fetch!(item, :created_at)
    view_count = Map.fetch!(item, :view_count)
    comment_count = Map.fetch!(item, :comment_count)

    net_votes = upvotes - downvotes

    age_hours = max(now - created_at, 0) / @seconds_per_hour
    recency = :math.pow(2, -age_hours / half_life_hours)

    engagement = if view_count > 0, do: comment_count / view_count, else: 0.0

    weights.votes * net_votes +
      weights.recency * recency +
      weights.engagement * engagement
  end

  @doc """
  Returns `items` sorted by score, highest first.

  The same `opts` are passed through to `score/2`, so ranking honors any custom
  `:now`, `:half_life_hours`, or `:weights`.

  Ties are broken, in order, by:

    1. Higher score first.
    2. More recently created item (larger `:created_at`) first.
    3. Original relative order (stable sort).
  """
  @spec rank([map()], keyword()) :: [map()]
  def rank(items, opts \\ []) when is_list(items) and is_list(opts) do
    items
    |> Enum.map(fn item -> {score(item, opts), Map.fetch!(item, :created_at), item} end)
    |> Enum.sort(fn {score_a, created_a, _a}, {score_b, created_b, _b} ->
      cond do
        score_a > score_b -> true
        score_a < score_b -> false
        created_a > created_b -> true
        created_a < created_b -> false
        # Equal score and created_at: keep original order (stable sort).
        true -> true
      end
    end)
    |> Enum.map(fn {_score, _created_at, item} -> item end)
  end
end
```

## New specification

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
