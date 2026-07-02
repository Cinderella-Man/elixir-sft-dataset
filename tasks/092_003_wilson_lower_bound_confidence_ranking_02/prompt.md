# Ranking — implement `score/2`

Implement the public `score/2` function for the `Ranking` module. It computes the
lower bound of the **Wilson score confidence interval** for the proportion of
upvotes on an item, returned as a float.

The function takes an `item` map (with atom keys `:upvotes` and `:downvotes`,
both non-negative integers) and an optional keyword list `opts`. Read the
z-score from `opts` under the `:z` key, defaulting to the module attribute
`@default_z` (`1.96`, ≈ 95% confidence); a larger `z` widens the interval and
lowers the score.

Fetch `:upvotes` and `:downvotes` from the item and let `n = upvotes + downvotes`.
If `n == 0`, return exactly `0.0` (the function must never raise on a zero-vote
item). Otherwise, with `p = upvotes / n` and `z2 = z * z`, compute:

```
denominator = 1 + z2 / n
center      = p + z2 / (2 * n)
margin      = z * sqrt( (p * (1 - p) + z2 / (4 * n)) / n )
score       = (center - margin) / denominator
```

using `:math.sqrt/1` for the square root, and return `score`. Keep the existing
guard clause and default argument. The item is never mutated.

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
    # TODO
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