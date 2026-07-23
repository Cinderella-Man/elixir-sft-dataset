# The tests are the spec

Below is a complete, self-contained ExUnit suite. It is the only
specification you get: build the module (or modules) it exercises until
every test passes. Reach for nothing beyond what the tests themselves
require — the standard library and OTP unless the suite says otherwise.
House style applies (`@moduledoc`, `@doc` + `@spec` on the public API,
no compiler warnings).

## The test suite

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

Send back the implementation only — one file, no tests.
