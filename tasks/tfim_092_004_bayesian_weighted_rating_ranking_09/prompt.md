# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule RankingTest do
  use ExUnit.Case, async: false

  defp item(overrides) do
    base = %{id: nil, rating: 0.0, vote_count: 0}
    Map.merge(base, Map.new(overrides))
  end

  defp ids(items), do: Enum.map(items, & &1.id)

  # -------------------------------------------------------
  # score/2 — exact formula
  # -------------------------------------------------------

  test "score matches the weighted-rating formula with explicit mean/min_votes" do
    # (100/125)*9.0 + (25/125)*8.5 = 7.2 + 1.7 = 8.9
    it = item(rating: 9.0, vote_count: 100)
    assert_in_delta Ranking.score(it, mean: 8.5, min_votes: 25), 8.9, 1.0e-9
  end

  test "score is a float" do
    assert is_float(Ranking.score(item(rating: 7.0, vote_count: 3), mean: 6.0))
  end

  test "an item with no votes scores exactly the prior mean" do
    it = item(rating: 10.0, vote_count: 0)
    assert_in_delta Ranking.score(it, mean: 6.0, min_votes: 25), 6.0, 1.0e-9
  end

  test "no votes with default options never raises and yields the default mean 0.0" do
    assert Ranking.score(item(rating: 5.0, vote_count: 0)) === 0.0
  end

  test "zero denominator (min_votes 0, no votes) returns the mean without raising" do
    it = item(rating: 4.0, vote_count: 0)
    assert_in_delta Ranking.score(it, mean: 3.5, min_votes: 0), 3.5, 1.0e-9
  end

  test "a larger min_votes pulls a low-vote item more strongly toward the mean" do
    it = item(rating: 10.0, vote_count: 10)
    # m=25 -> (10/35)*10 + (25/35)*5 = 6.428571...
    # m=100 -> (10/110)*10 + (100/110)*5 = 5.454545...
    s_small_m = Ranking.score(it, mean: 5.0, min_votes: 25)
    s_large_m = Ranking.score(it, mean: 5.0, min_votes: 100)

    assert_in_delta s_small_m, 6.4285714, 1.0e-6
    assert_in_delta s_large_m, 5.4545454, 1.0e-6
    assert s_large_m < s_small_m
    assert s_large_m > 5.0
  end

  # -------------------------------------------------------
  # rank/2 — corpus-aware ordering
  # -------------------------------------------------------

  test "rank computes the corpus mean and pulls low-vote items down" do
    a = item(id: :a, rating: 9.0, vote_count: 100)
    b = item(id: :b, rating: 9.5, vote_count: 3)
    c = item(id: :c, rating: 7.0, vote_count: 1000)

    # corpus mean = (9.0 + 9.5 + 7.0) / 3 = 8.5, min_votes = 25 (default)
    ranked = Ranking.rank([b, c, a])
    assert ids(ranked) == [:a, :b, :c]

    # And the actual scores against the auto-computed mean:
    assert_in_delta Ranking.score(a, mean: 8.5), 8.9, 1.0e-9
    assert_in_delta Ranking.score(b, mean: 8.5), 8.6071428, 1.0e-6
    assert_in_delta Ranking.score(c, mean: 8.5), 7.0365853, 1.0e-6
  end

  test "an explicit :mean overrides the computed corpus mean" do
    # TODO
  end

  test "rank returns the item maps unchanged" do
    a = item(id: :a, rating: 8.0, vote_count: 40)
    b = item(id: :b, rating: 6.0, vote_count: 5)
    ranked = Ranking.rank([a, b])
    assert Enum.sort_by(ranked, & &1.id) == Enum.sort_by([a, b], & &1.id)
  end

  # -------------------------------------------------------
  # Tie-breaking
  # -------------------------------------------------------

  test "ties on score are broken by vote_count descending" do
    # rating == mean => score == mean regardless of vote_count => scores tie.
    low = item(id: :low, rating: 8.0, vote_count: 5)
    high = item(id: :high, rating: 8.0, vote_count: 100)

    assert ids(Ranking.rank([low, high], mean: 8.0, min_votes: 25)) == [:high, :low]
    assert ids(Ranking.rank([high, low], mean: 8.0, min_votes: 25)) == [:high, :low]
  end

  test "fully-equal items preserve original input order (stable)" do
    x = item(id: :x, rating: 7.0, vote_count: 10)
    y = item(id: :y, rating: 7.0, vote_count: 10)
    z = item(id: :z, rating: 7.0, vote_count: 10)

    assert ids(Ranking.rank([x, y, z], mean: 7.0)) == [:x, :y, :z]
    assert ids(Ranking.rank([z, x, y], mean: 7.0)) == [:z, :x, :y]
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "rank handles the empty list" do
    assert Ranking.rank([]) == []
  end

  test "rank handles a single item" do
    only = item(id: :only, rating: 8.0, vote_count: 42)
    assert Ranking.rank([only]) == [only]
  end
end
```
