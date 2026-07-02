# Ranking — implement `score/2`

You are given the `Ranking` module below with every function already written
**except** the body of the public function `score/2`, which has been replaced
with `# TODO`. Implement it.

## What `score/2` must do

`Ranking.score(item, opts \\ [])` computes the **Bayesian weighted rating** of a
single `item` and returns it as a **float**.

An `item` is a plain map with at least these atom keys:

- `:rating` — the item's own average rating, a number (fetch it with
  `Map.fetch!/2`)
- `:vote_count` — a non-negative integer (fetch it with `Map.fetch!/2`)

Read two options from `opts` (a keyword list):

- `:min_votes` — the prior weight `m`. Defaults to `@default_min_votes` (`25`).
- `:mean` — the prior mean `C`. Defaults to `0.0`.

Let `v = vote_count`, `R = rating`, `m = min_votes`, `C = mean`, and
`denom = v + m`. Then compute exactly:

```
score = (v / (v + m)) * R + (m / (v + m)) * C
```

Requirements and edge cases:

- If `denom == 0` (only possible when both `vote_count` and `:min_votes` are
  `0`), return `C` — but as a float, so return `1.0 * C`. The function must
  never raise or divide by zero.
- The result must be a float in every branch.
- Do not mutate the item and do not read any keys beyond `:rating` and
  `:vote_count`.

## The module

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
    # TODO
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
  @spec rank([map()], keyword()) :: [map()]
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