  test "ties on score are broken by created_at descending" do
    # A: net 10 -> order 1.0, at epoch -> score 1.0
    # B: net 1  -> order 0.0, at epoch + divisor -> time term 1.0 -> score 1.0
    a = item(id: :a, upvotes: 10, created_at: @epoch)
    b = item(id: :b, upvotes: 1, created_at: @epoch + @divisor)

    assert_in_delta Ranking.score(a, opts()), Ranking.score(b, opts()), 1.0e-9
    assert ids(Ranking.rank([a, b], opts())) == [:b, :a]
    assert ids(Ranking.rank([b, a], opts())) == [:b, :a]
  end