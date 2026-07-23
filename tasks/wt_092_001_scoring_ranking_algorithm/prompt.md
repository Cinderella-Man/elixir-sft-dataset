# Write the test harness

Module and original specification below. Produce the ExUnit harness that
verifies a correct implementation.

Hard requirements:
- Test module: `<Module>Test`, `use ExUnit.Case, async: false`.
- No `ExUnit.start()` (the evaluator owns startup).
- Self-contained single file: inline any fakes, clock Agents, and helpers.
- Full public API coverage plus the specification's edge cases.
- Compiles with zero warnings (`_`-prefix unused variables; float zero
  matches as `+0.0`/`-0.0`).

## Original specification

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

## Module under test

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
