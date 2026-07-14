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

# Ranking — a Reddit-style logarithmic "hot" score

Write me an Elixir module called `Ranking` that scores and ranks content items
(posts, links, comments) using the classic **Reddit "hot" algorithm**: a
logarithmic vote term added to a linear time term.

Use only the Elixir/Erlang standard library — no external dependencies. Put
everything in a single module.

## The item shape

Each item is a plain map with atom keys:

- `:upvotes` — non-negative integer
- `:downvotes` — non-negative integer
- `:created_at` — an integer Unix timestamp in **seconds**

Items may carry additional keys (e.g. an `:id`); ignore anything you don't
need, and `rank/2` must return the item maps **unchanged**.

## Public API

### `Ranking.score(item, opts \\ [])` → float

Computes the hot score of a single item as a float, using exactly this formula:

```
net_votes = upvotes - downvotes                     # may be negative

order = log10(max(abs(net_votes), 1))               # log10(1) == 0.0

sign  = 1  if net_votes > 0
        -1 if net_votes < 0
        0  if net_votes == 0

seconds = created_at - epoch                         # may be negative

score = round(sign * order + seconds / divisor, 7)   # 7 decimal places
```

Supported options (all optional):

- `:epoch` — integer Unix timestamp (seconds) used as the time origin.
  Defaults to `1_134_028_003` (Reddit's historical epoch).
- `:divisor` — a positive number controlling how much a fixed amount of elapsed
  time is worth relative to an order-of-magnitude of votes. Defaults to `45_000`
  (so `45_000` seconds ≈ 12.5 hours is worth `+1.0`, the same as a 10× jump in
  net votes).

Notes:

- The vote contribution grows **logarithmically**: going from 10 → 100 net votes
  adds the same `1.0` that going from 1 → 10 adds. Vote counts have diminishing
  returns.
- `net_votes == 0` contributes `0.0` from the vote term (`sign` is `0`).
- The result is rounded to 7 decimal places with `Float.round/2`.

### `Ranking.rank(items, opts \\ [])` → list of items

Returns the items sorted by score **descending** (highest score first),
threading the same `opts` through to the scoring.

Tie-breaking rules, applied in order:

1. Higher score first.
2. If scores are equal, the more recently created item (larger `:created_at`)
   comes first.
3. If both score and `:created_at` are equal, preserve the items' original
   relative order (stable sort).

`rank/2` must handle the empty list and a single-item list gracefully.

## Behavioral expectations

- Given equal votes, a **newer** item ranks above an **older** one.
- Given equal age, a **more upvoted** item ranks above one with fewer net votes.
- Heavily downvoted items (negative net votes) sink toward the bottom.
- Cranking the `:divisor` down makes time dominate; cranking it up makes votes
  dominate.

Give me the complete `Ranking` module in a single file.
