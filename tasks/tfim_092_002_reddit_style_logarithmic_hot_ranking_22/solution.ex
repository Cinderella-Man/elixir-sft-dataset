  test "extra item keys are ignored and returned untouched by rank" do
    a = item(id: :a, upvotes: 10, created_at: @epoch) |> Map.merge(%{title: "a", tags: [:x]})

    b =
      item(id: :b, upvotes: 1000, created_at: @epoch) |> Map.merge(%{author: "b", score: :bogus})

    assert_in_delta Ranking.score(a, opts()), 1.0, 1.0e-9
    assert Ranking.rank([a, b], opts()) == [b, a]
  end