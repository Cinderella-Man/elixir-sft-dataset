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
  A Bayesian weighted-rating ("IMDb Top 250") ranking for rated content items.

  Each item is a plain map with atom keys:

    * `:rating` — the item's own average rating, a number
    * `:vote_count` — non-negative integer

  Items may carry any number of additional keys (such as an `:id`); those are
  ignored and items are never mutated.

  The weighted rating pulls each item's rating toward a prior mean in inverse
  proportion to its vote count:

      score = (v / (v + m)) * R + (m / (v + m)) * C

  where `v` is the vote count, `R` the rating, `m` the prior weight
  (`:min_votes`), and `C` the prior mean (`:mean`). When ranking a list without
  an explicit `:mean`, `C` is the mean rating across the list.
  """

  @default_min_votes 25

  @doc """
  Computes the weighted rating of a single `item` as a float.

  ## Options

    * `:min_votes` — the prior weight `m`. Defaults to `25`.
    * `:mean` — the prior mean `C`. Defaults to `0.0`.
  """
  @spec score(map(), keyword()) :: float()
  def score(item, opts \\ []) when is_map(item) and is_list(opts) do
    m = Keyword.get(opts, :min_votes, @default_min_votes)
    c = Keyword.get(opts, :mean, 0.0)

    r = Map.fetch!(item, :rating)
    v = Map.fetch!(item, :vote_count)

    denom = v + m

    if denom == 0 do
      1.0 * c
    else
      v / denom * r + m / denom * c
    end
  end

  @doc """
  Returns `items` sorted by weighted rating, highest first.

  Corpus-aware: when `opts` lacks `:mean`, the prior mean `C` is computed as the
  arithmetic mean of the `:rating` values across `items` (`0.0` for an empty
  list). `:min_votes` is threaded through unchanged.

  Ties are broken, in order, by:

    1. Higher score first.
    2. More `:vote_count` first.
    3. Original relative order (stable sort).
  """
  # TODO: @spec
  def rank(items, opts \\ []) when is_list(items) and is_list(opts) do
    opts =
      if Keyword.has_key?(opts, :mean) do
        opts
      else
        Keyword.put(opts, :mean, corpus_mean(items))
      end

    items
    |> Enum.map(fn item -> {score(item, opts), Map.fetch!(item, :vote_count), item} end)
    |> Enum.sort(fn {score_a, votes_a, _a}, {score_b, votes_b, _b} ->
      cond do
        score_a > score_b -> true
        score_a < score_b -> false
        votes_a > votes_b -> true
        votes_a < votes_b -> false
        true -> true
      end
    end)
    |> Enum.map(fn {_score, _votes, item} -> item end)
  end

  defp corpus_mean([]), do: 0.0

  defp corpus_mean(items) do
    ratings = Enum.map(items, &Map.fetch!(&1, :rating))
    Enum.sum(ratings) / length(ratings)
  end
end
```

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
