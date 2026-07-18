# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

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

The result must always be a **float** (e.g. `3.0`, never the integer `3`), even
when `:mean`, `:rating`, or `:min_votes` are given as integers.

Supported options (all optional):

- `:min_votes` — the prior weight `m`, a non-negative number. Defaults to `25`.
  A larger `m` pulls low-vote items more strongly toward the mean.
- `:mean` — the prior mean `C`. Defaults to `0.0`.

Notes:

- If `v + m == 0` (only possible when both `vote_count` and `:min_votes` are 0),
  return `C` as a float. The function must never raise or divide by zero.
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
