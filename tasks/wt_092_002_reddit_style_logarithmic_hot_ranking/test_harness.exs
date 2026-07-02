defmodule RankingTest do
  use ExUnit.Case, async: false

  # Deterministic time origin and divisor for every test.
  @epoch 1_600_000_000
  @divisor 45_000

  defp item(overrides) do
    base = %{id: nil, upvotes: 0, downvotes: 0, created_at: @epoch}
    Map.merge(base, Map.new(overrides))
  end

  defp ids(items), do: Enum.map(items, & &1.id)

  defp opts, do: [epoch: @epoch, divisor: @divisor]

  # -------------------------------------------------------
  # score/2 — exact formula
  # -------------------------------------------------------

  test "at the epoch, score is just the logarithmic vote term" do
    # net 10 -> log10(10) = 1.0 ; net 100 -> log10(100) = 2.0
    assert_in_delta Ranking.score(item(upvotes: 10, created_at: @epoch), opts()), 1.0, 1.0e-9
    assert_in_delta Ranking.score(item(upvotes: 100, created_at: @epoch), opts()), 2.0, 1.0e-9
  end

  test "score is a float" do
    assert is_float(Ranking.score(item(upvotes: 3, created_at: @epoch), opts()))
  end

  test "vote term grows logarithmically (10x votes adds a constant)" do
    s10 = Ranking.score(item(upvotes: 10, created_at: @epoch), opts())
    s100 = Ranking.score(item(upvotes: 100, created_at: @epoch), opts())
    s1000 = Ranking.score(item(upvotes: 1000, created_at: @epoch), opts())

    assert_in_delta s100 - s10, 1.0, 1.0e-9
    assert_in_delta s1000 - s100, 1.0, 1.0e-9
  end

  test "net_votes of zero contributes nothing from the vote term" do
    it = item(upvotes: 5, downvotes: 5, created_at: @epoch)
    assert_in_delta Ranking.score(it, opts()), 0.0, 1.0e-9
  end

  test "negative net votes make the vote term negative" do
    it = item(upvotes: 0, downvotes: 10, created_at: @epoch)
    # sign = -1, order = log10(10) = 1.0 -> -1.0
    assert_in_delta Ranking.score(it, opts()), -1.0, 1.0e-9
  end

  test "time term is additive and linear in elapsed seconds" do
    # net 1 -> order 0 ; created one divisor-worth of seconds after epoch -> +1.0
    it = item(upvotes: 1, created_at: @epoch + @divisor)
    assert_in_delta Ranking.score(it, opts()), 1.0, 1.0e-9
  end

  test "divisor is configurable" do
    it = item(upvotes: 1, created_at: @epoch + 90_000)
    # net 1 -> order 0 ; 90_000 / 45_000 = 2.0
    assert_in_delta Ranking.score(it, epoch: @epoch, divisor: 45_000), 2.0, 1.0e-9
    # 90_000 / 90_000 = 1.0
    assert_in_delta Ranking.score(it, epoch: @epoch, divisor: 90_000), 1.0, 1.0e-9
  end

  # -------------------------------------------------------
  # Relative ordering
  # -------------------------------------------------------

  test "newer item ranks above an older one with equal votes" do
    recent = item(id: :recent, upvotes: 50, created_at: @epoch)
    old = item(id: :old, upvotes: 50, created_at: @epoch - 100 * @divisor)
    assert Ranking.score(recent, opts()) > Ranking.score(old, opts())
  end

  test "more net votes ranks above fewer given equal age" do
    high = item(id: :high, upvotes: 100, created_at: @epoch)
    low = item(id: :low, upvotes: 2, created_at: @epoch)
    assert Ranking.score(high, opts()) > Ranking.score(low, opts())
  end

  test "rank sorts items by score descending" do
    a = item(id: :a, upvotes: 1000, created_at: @epoch)
    b = item(id: :b, upvotes: 10, created_at: @epoch)
    c = item(id: :c, upvotes: 0, downvotes: 100, created_at: @epoch)

    assert ids(Ranking.rank([c, b, a], opts())) == [:a, :b, :c]
  end

  test "rank returns the item maps unchanged" do
    a = item(id: :a, upvotes: 5, created_at: @epoch)
    b = item(id: :b, upvotes: 9, created_at: @epoch)
    ranked = Ranking.rank([a, b], opts())
    assert Enum.sort_by(ranked, & &1.id) == Enum.sort_by([a, b], & &1.id)
  end

  # -------------------------------------------------------
  # Tie-breaking
  # -------------------------------------------------------

  test "ties on score are broken by created_at descending" do
    # A: net 10 -> order 1.0, at epoch -> score 1.0
    # B: net 1  -> order 0.0, at epoch + divisor -> time term 1.0 -> score 1.0
    a = item(id: :a, upvotes: 10, created_at: @epoch)
    b = item(id: :b, upvotes: 1, created_at: @epoch + @divisor)

    assert_in_delta Ranking.score(a, opts()), Ranking.score(b, opts()), 1.0e-9
    assert ids(Ranking.rank([a, b], opts())) == [:b, :a]
    assert ids(Ranking.rank([b, a], opts())) == [:b, :a]
  end

  test "fully-equal items preserve original input order (stable)" do
    x = item(id: :x, upvotes: 7, created_at: @epoch)
    y = item(id: :y, upvotes: 7, created_at: @epoch)
    z = item(id: :z, upvotes: 7, created_at: @epoch)

    assert ids(Ranking.rank([x, y, z], opts())) == [:x, :y, :z]
    assert ids(Ranking.rank([z, x, y], opts())) == [:z, :x, :y]
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "rank handles the empty list" do
    assert Ranking.rank([], opts()) == []
  end

  test "rank handles a single item" do
    only = item(id: :only, upvotes: 3, created_at: @epoch)
    assert Ranking.rank([only], opts()) == [only]
  end
end