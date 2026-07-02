# Implement `Ranking.score/2`

Implement the public `score/2` function. It takes an `item` map and a keyword list
`opts` (defaulting to `[]`), and returns the item's "hot score" as a float.

First, read the options, each with a default:

- `:now` — the current-time reference (integer Unix seconds), defaulting to
  `System.os_time(:second)`.
- `:half_life_hours` — how fast recency decays, defaulting to
  `@default_half_life_hours`.
- `:weights` — a map **merged over** `@default_weights` so callers may override any
  subset of the `:votes`, `:recency`, and `:engagement` weights.

Then fetch the five required fields from the item with `Map.fetch!/2`: `:upvotes`,
`:downvotes`, `:created_at`, `:view_count`, and `:comment_count`.

Compute the score using exactly this formula:

- `net_votes` is `upvotes - downvotes` (may be negative).
- `age_hours` is `max(now - created_at, 0) / @seconds_per_hour` — clamped so a
  "future" item is treated as age `0`, never negative.
- `recency` is `2` raised to the power `-age_hours / half_life_hours` (use
  `:math.pow/2`): `1.0` at age `0`, `0.5` at one half-life.
- `engagement` is `comment_count / view_count` when `view_count > 0`, otherwise
  `0.0` (never raise on a zero view count).

Finally return the weighted sum:

```
weights.votes * net_votes + weights.recency * recency + weights.engagement * engagement
```

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
    # TODO
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