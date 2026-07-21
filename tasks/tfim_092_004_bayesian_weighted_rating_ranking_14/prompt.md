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
    a = item(id: :a, rating: 9.0, vote_count: 100)
    _b = item(id: :b, rating: 9.5, vote_count: 3)

    # With mean forced very high, the low-vote high-rating item is pulled UP
    # toward the mean less harshly than the high-vote one, but both are near
    # the mean; verify the score uses 12.0, not the corpus mean of 9.25.
    assert_in_delta Ranking.score(a, mean: 12.0), 9.0 * (100 / 125) + 12.0 * (25 / 125), 1.0e-9
  end

  test "rank scores with a caller-supplied :mean that differs from the corpus mean" do
    a = item(id: :a, rating: 9.0, vote_count: 100)
    b = item(id: :b, rating: 9.5, vote_count: 3)

    # Corpus mean = (9.0 + 9.5) / 2 = 9.25, m = 25:
    #   a -> (100/125)*9.0 + (25/125)*9.25  = 9.05
    #   b -> (3/28)*9.5   + (25/28)*9.25    = 9.2767...  => b outranks a.
    assert ids(Ranking.rank([a, b])) == [:b, :a]

    # With C = 0.0 supplied verbatim, the 3-vote item is crushed toward 0:
    #   a -> (100/125)*9.0 = 7.2
    #   b -> (3/28)*9.5    = 1.0178...      => a outranks b.
    assert ids(Ranking.rank([a, b], mean: 0.0)) == [:a, :b]
    assert ids(Ranking.rank([b, a], mean: 0.0)) == [:a, :b]
  end

  test "rank threads a non-default :min_votes through to every score" do
    p = item(id: :p, rating: 9.5, vote_count: 10)
    q = item(id: :q, rating: 9.0, vote_count: 100)
    r = item(id: :r, rating: 3.0, vote_count: 1000)

    # corpus mean = (9.5 + 9.0 + 3.0) / 3 = 7.1666...
    # m = 25 (default): p -> 7.8333..., q -> 8.6333... => q ahead of p.
    assert ids(Ranking.rank([p, q, r])) == [:q, :p, :r]

    # m = 1: barely any smoothing, so the raw ratings decide:
    #   p -> (10/11)*9.5 + (1/11)*7.1666... = 9.2878...
    #   q -> (100/101)*9.0 + (1/101)*7.1666... = 8.9818...  => p ahead of q.
    assert ids(Ranking.rank([p, q, r], min_votes: 1)) == [:p, :q, :r]
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
    # TODO
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

  test "rating equal to the mean scores exactly the mean at every vote count" do
    for v <- [0, 1, 25, 1_000, 100_000] do
      it = item(rating: 8.5, vote_count: v)
      assert_in_delta Ranking.score(it, mean: 8.5, min_votes: 25), 8.5, 1.0e-9
      assert_in_delta Ranking.score(it, mean: 8.5, min_votes: 100), 8.5, 1.0e-9
    end
  end

  test "a no-vote item lands at the corpus mean between a stronger and a weaker item" do
    a = item(id: :a, rating: 9.0, vote_count: 100)
    b = item(id: :b, rating: 6.0, vote_count: 0)
    c = item(id: :c, rating: 3.0, vote_count: 100)

    # corpus mean = (9.0 + 6.0 + 3.0) / 3 = 6.0, m = 25 (default):
    #   a -> (100/125)*9.0 + (25/125)*6.0 = 8.4
    #   b -> no votes                     = 6.0  (exactly the corpus mean)
    #   c -> (100/125)*3.0 + (25/125)*6.0 = 3.6
    assert ids(Ranking.rank([c, b, a])) == [:a, :b, :c]
    assert_in_delta Ranking.score(b, mean: 6.0), 6.0, 1.0e-9
  end

  test "rank threads min_votes 0 so a no-vote item still scores at the corpus mean" do
    a = item(id: :a, rating: 9.0, vote_count: 10)
    b = item(id: :b, rating: 5.0, vote_count: 0)
    c = item(id: :c, rating: 1.0, vote_count: 10)

    # corpus mean = (9.0 + 5.0 + 1.0) / 3 = 5.0, m = 0:
    #   a -> (10/10)*9.0 = 9.0
    #   b -> v + m == 0  = 5.0 (the corpus mean, no raise)
    #   c -> (10/10)*1.0 = 1.0
    assert ids(Ranking.rank([c, b, a], min_votes: 0)) == [:a, :b, :c]
  end

  test "score with no options at all uses the documented defaults m = 25 and C = 0.0" do
    # (25/50)*8.0 + (25/50)*0.0 = 4.0
    assert_in_delta Ranking.score(item(rating: 8.0, vote_count: 25)), 4.0, 1.0e-9
    # (75/100)*8.0 + (25/100)*0.0 = 6.0
    assert_in_delta Ranking.score(item(rating: 8.0, vote_count: 75)), 6.0, 1.0e-9
  end

  test "score returns a float in the zero-denominator branch given an integer mean" do
    it = item(rating: 4, vote_count: 0)
    assert is_float(Ranking.score(it, mean: 3, min_votes: 0))
    assert Ranking.score(it, mean: 3, min_votes: 0) === 3.0
    assert is_float(Ranking.score(item(rating: 4, vote_count: 10), mean: 3, min_votes: 0))
  end

  # -------------------------------------------------------
  # rank/2 — caller-supplied :mean is used verbatim, not recomputed
  # -------------------------------------------------------

  test "rank uses a caller-supplied :mean verbatim rather than the corpus mean" do
    a = item(id: :a, rating: 9.0, vote_count: 100)
    b = item(id: :b, rating: 9.5, vote_count: 3)

    # Corpus mean = (9.0 + 9.5) / 2 = 9.25; scoring against 9.25 would place the
    # 3-vote item first ([:b, :a]). With C = 5.0 supplied verbatim the low-vote
    # item is dragged well below the high-vote one, so the order flips:
    #   a -> (100/125)*9.0 + (25/125)*5.0 = 8.2
    #   b -> (3/28)*9.5    + (25/28)*5.0  = 5.4821...  => a outranks b.
    assert ids(Ranking.rank([a, b], mean: 5.0)) == [:a, :b]
    assert ids(Ranking.rank([b, a], mean: 5.0)) == [:a, :b]
  end

  test "rank threads a large non-default :min_votes that reorders the result" do
    p = item(id: :p, rating: 10.0, vote_count: 100)
    q = item(id: :q, rating: 8.5, vote_count: 300)

    # With C = 5.0 supplied verbatim and the default m = 25 the high-rating item
    # leads:
    #   p -> (100/125)*10.0 + (25/125)*5.0 = 9.0
    #   q -> (300/325)*8.5  + (25/325)*5.0 = 8.2307...  => p ahead of q.
    assert ids(Ranking.rank([p, q], mean: 5.0)) == [:p, :q]

    # A large m = 300 pulls the lower-vote item toward the mean much harder,
    # flipping the order:
    #   p -> (100/400)*10.0 + (300/400)*5.0 = 6.25
    #   q -> (300/600)*8.5  + (300/600)*5.0 = 6.75   => q ahead of p.
    assert ids(Ranking.rank([p, q], mean: 5.0, min_votes: 300)) == [:q, :p]
    assert ids(Ranking.rank([q, p], mean: 5.0, min_votes: 300)) == [:q, :p]
  end
end
```
