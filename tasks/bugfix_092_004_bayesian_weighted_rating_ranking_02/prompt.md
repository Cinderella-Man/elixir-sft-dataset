# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

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

Supported options (all optional):

- `:min_votes` — the prior weight `m`, a non-negative number. Defaults to `25`.
  A larger `m` pulls low-vote items more strongly toward the mean.
- `:mean` — the prior mean `C`. Defaults to `0.0`.

Notes:

- If `v + m == 0` (only possible when both `vote_count` and `:min_votes` are 0),
  return `C`. The function must never raise or divide by zero.
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

## The buggy module

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
        score_a >= score_b -> true
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

## Failing test report

```
1 of 13 test(s) failed:

  * test ties on score are broken by vote_count descending
      
      
      Assertion with == failed
      code:  assert ids(Ranking.rank([low, high], mean: 8.0, min_votes: 25)) == [:high, :low]
      left:  [:low, :high]
      right: [:high, :low]
```
