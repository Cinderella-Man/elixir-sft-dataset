# Write tests for this module

Below is a completed Elixir module and the original specification it was built to
satisfy. Write a comprehensive ExUnit test harness that verifies a correct
implementation of this module.

Requirements for the harness:
- Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
- Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
- Make it self-contained: any fakes, clock Agents, or helpers are defined inline.
- Cover the full public API and the important edge cases described in the spec.
- It must compile with ZERO warnings (prefix unused variables with `_`; match float
  zero as `+0.0`/`-0.0`).
- Give me the complete harness in a single file.

## Original specification

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

## Module under test

```elixir
defmodule Ranking do
  @moduledoc """
  A Reddit-style logarithmic "hot" ranking for content items.

  Each item is a plain map with atom keys:

    * `:upvotes` — non-negative integer
    * `:downvotes` — non-negative integer
    * `:created_at` — integer Unix timestamp in seconds

  Items may carry any number of additional keys (such as an `:id`); those are
  ignored and items are never mutated.

  The hot score blends a logarithmic vote term with a linear time term:

      net_votes = upvotes - downvotes
      order     = log10(max(abs(net_votes), 1))
      sign      = 1 | -1 | 0   (per the sign of net_votes)
      seconds   = created_at - epoch
      score     = round(sign * order + seconds / divisor, 7)
  """

  @default_epoch 1_134_028_003
  @default_divisor 45_000

  @doc """
  Computes the hot score of a single `item` as a float.

  ## Options

    * `:epoch` — integer Unix timestamp (seconds) used as the time origin.
      Defaults to `1_134_028_003`.
    * `:divisor` — a positive number controlling the weight of elapsed time
      relative to an order-of-magnitude of votes. Defaults to `45_000`.
  """
  @spec score(map(), keyword()) :: float()
  def score(item, opts \\ []) when is_map(item) and is_list(opts) do
    epoch = Keyword.get(opts, :epoch, @default_epoch)
    divisor = Keyword.get(opts, :divisor, @default_divisor)

    upvotes = Map.fetch!(item, :upvotes)
    downvotes = Map.fetch!(item, :downvotes)
    created_at = Map.fetch!(item, :created_at)

    net_votes = upvotes - downvotes
    order = :math.log10(max(abs(net_votes), 1))

    sign =
      cond do
        net_votes > 0 -> 1
        net_votes < 0 -> -1
        true -> 0
      end

    seconds = created_at - epoch

    Float.round(sign * order + seconds / divisor, 7)
  end

  @doc """
  Returns `items` sorted by score, highest first.

  The same `opts` are passed through to `score/2`.

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
        true -> true
      end
    end)
    |> Enum.map(fn {_score, _created_at, item} -> item end)
  end
end
```
