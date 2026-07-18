  test "rank returns the item maps unchanged" do
    a = item(id: :a, upvotes: 5, created_at: @epoch)
    b = item(id: :b, upvotes: 9, created_at: @epoch)
    ranked = Ranking.rank([a, b], opts())
    assert Enum.sort_by(ranked, & &1.id) == Enum.sort_by([a, b], & &1.id)
  end