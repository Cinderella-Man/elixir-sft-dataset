defmodule RankingTest do
  use ExUnit.Case, async: false

  defp item(overrides) do
    base = %{id: nil, upvotes: 0, downvotes: 0}
    Map.merge(base, Map.new(overrides))
  end

  defp ids(items), do: Enum.map(items, & &1.id)

  # -------------------------------------------------------
  # score/2 — exact formula (against known Wilson values)
  # -------------------------------------------------------

  test "1 upvote / 0 downvotes matches the known Wilson lower bound" do
    assert_in_delta Ranking.score(item(upvotes: 1, downvotes: 0)), 0.2065432, 1.0e-6
  end

  test "10 upvotes / 0 downvotes matches the known Wilson lower bound" do
    assert_in_delta Ranking.score(item(upvotes: 10, downvotes: 0)), 0.7224598, 1.0e-6
  end

  test "score is a float" do
    assert is_float(Ranking.score(item(upvotes: 3, downvotes: 1)))
  end

  test "no votes scores exactly 0.0 and never raises" do
    assert Ranking.score(item(upvotes: 0, downvotes: 0)) === 0.0
  end

  # -------------------------------------------------------
  # Behavioral properties
  # -------------------------------------------------------

  test "more votes at the same ratio raise the score" do
    small = Ranking.score(item(upvotes: 1, downvotes: 0))
    big = Ranking.score(item(upvotes: 10, downvotes: 0))
    assert big > small
  end

  test "adding a downvote lowers the score" do
    clean = Ranking.score(item(upvotes: 10, downvotes: 0))
    dinged = Ranking.score(item(upvotes: 10, downvotes: 1))
    assert dinged < clean
  end

  test "proven quality beats uncertain perfection" do
    perfect_tiny = Ranking.score(item(upvotes: 1, downvotes: 0))
    strong_large = Ranking.score(item(upvotes: 50, downvotes: 10))
    assert strong_large > perfect_tiny
  end

  test "larger sample with a higher ratio wins convincingly" do
    a = Ranking.score(item(upvotes: 100, downvotes: 10))
    b = Ranking.score(item(upvotes: 5, downvotes: 1))
    assert a > b
  end

  test "a higher z (more confidence demanded) lowers the score" do
    it = item(upvotes: 10, downvotes: 2)
    s95 = Ranking.score(it, z: 1.96)
    s99 = Ranking.score(it, z: 2.58)
    assert s99 < s95
  end

  # -------------------------------------------------------
  # rank/2 — ordering
  # -------------------------------------------------------

  test "rank sorts items by score descending" do
    a = item(id: :a, upvotes: 100, downvotes: 5)
    b = item(id: :b, upvotes: 10, downvotes: 1)
    c = item(id: :c, upvotes: 1, downvotes: 0)
    d = item(id: :d, upvotes: 2, downvotes: 20)

    assert ids(Ranking.rank([c, d, a, b])) == [:a, :b, :c, :d]
  end

  test "rank returns the item maps unchanged" do
    a = item(id: :a, upvotes: 5, downvotes: 2)
    b = item(id: :b, upvotes: 9, downvotes: 0)
    ranked = Ranking.rank([a, b])
    assert Enum.sort_by(ranked, & &1.id) == Enum.sort_by([a, b], & &1.id)
  end

  test "identical items preserve original input order (stable)" do
    x = item(id: :x, upvotes: 7, downvotes: 1)
    y = item(id: :y, upvotes: 7, downvotes: 1)
    z = item(id: :z, upvotes: 7, downvotes: 1)

    assert ids(Ranking.rank([x, y, z])) == [:x, :y, :z]
    assert ids(Ranking.rank([z, x, y])) == [:z, :x, :y]
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "rank handles the empty list" do
    assert Ranking.rank([]) == []
  end

  test "rank handles a single item" do
    only = item(id: :only, upvotes: 3, downvotes: 1)
    assert Ranking.rank([only]) == [only]
  end
end
