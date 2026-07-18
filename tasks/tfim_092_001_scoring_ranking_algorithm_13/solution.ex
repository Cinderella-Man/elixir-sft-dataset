  test "rank returns the item maps unchanged" do
    a = item(id: :a, upvotes: 5, view_count: 10, comment_count: 2)
    b = item(id: :b, upvotes: 9)

    ranked = Ranking.rank([a, b], now: @now)
    assert Enum.sort_by(ranked, & &1.id) == Enum.sort_by([a, b], & &1.id)
  end