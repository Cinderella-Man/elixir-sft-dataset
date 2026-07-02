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
    b = item(id: :b, rating: 9.5, vote_count: 3)

    # With mean forced very high, the low-vote high-rating item is pulled UP
    # toward the mean less harshly than the high-vote one, but both are near
    # the mean; verify the score uses 12.0, not the corpus mean of 9.25.
    assert_in_delta Ranking.score(a, mean: 12.0), 9.0 * (100 / 125) + 12.0 * (25 / 125), 1.0e-9
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