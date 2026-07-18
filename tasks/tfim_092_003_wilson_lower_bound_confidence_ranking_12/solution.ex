  test "rank returns the item maps unchanged" do
    a = item(id: :a, upvotes: 5, downvotes: 2)
    b = item(id: :b, upvotes: 9, downvotes: 0)
    ranked = Ranking.rank([a, b])
    assert Enum.sort_by(ranked, & &1.id) == Enum.sort_by([a, b], & &1.id)
  end