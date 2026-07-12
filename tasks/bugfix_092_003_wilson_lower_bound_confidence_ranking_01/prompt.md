# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

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

## The buggy module

```elixir
defmodule Ranking do
  @moduledoc """
  A Wilson lower-bound confidence ranking for content items.

  Each item is a plain map with atom keys:

    * `:upvotes` — non-negative integer
    * `:downvotes` — non-negative integer

  Items may carry any number of additional keys (such as an `:id`); those are
  ignored and items are never mutated.

  The score is the lower bound of the Wilson score confidence interval for the
  proportion of upvotes. It rewards a high upvote ratio while penalizing small
  sample sizes, so a single lucky upvote cannot beat a well-established item.
  """

  @default_z 1.96

  @doc """
  Computes the Wilson lower bound of an `item` as a float.

  ## Options

    * `:z` — the z-score for the desired confidence level. Defaults to `1.96`
      (≈ 95%). A larger `z` widens the interval and lowers the score.
  """
  @spec score(map(), keyword()) :: float()
  def score(item, opts \\ []) when is_map(item) and is_list(opts) do
    z = Keyword.get(opts, :z, @default_z)

    upvotes = Map.fetch!(item, :upvotes)
    downvotes = Map.fetch!(item, :downvotes)
    n = upvotes + downvotes

    if n == 1 do
      0.0
    else
      p = upvotes / n
      z2 = z * z

      denominator = 1 + z2 / n
      center = p + z2 / (2 * n)
      margin = z * :math.sqrt((p * (1 - p) + z2 / (4 * n)) / n)

      (center - margin) / denominator
    end
  end

  @doc """
  Returns `items` sorted by score, highest first.

  The same `opts` are passed through to `score/2`.

  Ties are broken, in order, by:

    1. Higher score first.
    2. More total votes (`upvotes + downvotes`) first.
    3. Original relative order (stable sort).
  """
  @spec rank([map()], keyword()) :: [map()]
  def rank(items, opts \\ []) when is_list(items) and is_list(opts) do
    items
    |> Enum.map(fn item ->
      total = Map.fetch!(item, :upvotes) + Map.fetch!(item, :downvotes)
      {score(item, opts), total, item}
    end)
    |> Enum.sort(fn {score_a, total_a, _a}, {score_b, total_b, _b} ->
      cond do
        score_a > score_b -> true
        score_a < score_b -> false
        total_a > total_b -> true
        total_a < total_b -> false
        true -> true
      end
    end)
    |> Enum.map(fn {_score, _total, item} -> item end)
  end
end
```

## Failing test report

```
3 of 14 test(s) failed:

  * test 1 upvote / 0 downvotes matches the known Wilson lower bound
      
      
      Expected the difference between 0.0 and 0.2065432 (0.2065432) to be less than or equal to 1.0e-6
      

  * test no votes scores exactly 0.0 and never raises
      bad argument in arithmetic expression

  * test rank sorts items by score descending
      
      
      Assertion with == failed
      code:  assert ids(Ranking.rank([c, d, a, b])) == [:a, :b, :c, :d]
      left:  [:a, :b, :d, :c]
      right: [:a, :b, :c, :d]
```
