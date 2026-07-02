  test "score is a float" do
    assert is_float(Ranking.score(item(upvotes: 3, created_at: @epoch), opts()))
  end