# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`rank/2` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `rank/2`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `rank/2` missing

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

    if n == 0 do
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
  # TODO: @spec
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

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
