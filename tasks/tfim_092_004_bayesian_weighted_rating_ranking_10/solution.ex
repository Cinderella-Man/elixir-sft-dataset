  test "rank returns the item maps unchanged" do
    a = item(id: :a, rating: 8.0, vote_count: 40)
    b = item(id: :b, rating: 6.0, vote_count: 5)
    ranked = Ranking.rank([a, b])
    assert Enum.sort_by(ranked, & &1.id) == Enum.sort_by([a, b], & &1.id)
  end