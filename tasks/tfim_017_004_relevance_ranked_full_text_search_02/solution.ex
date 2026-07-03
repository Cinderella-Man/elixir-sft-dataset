  test "matches only scored products, ranked by relevance descending" do
    assert {:ok, %{data: data}} = Ranked.search(products(), %{"q" => "run"})

    # p1: name 'running' (3) + desc 'running' (1) = 4
    # p2: name 'runner' (3) + desc 'running' (1) = 4  -> tie broken by name asc
    assert ids(data) == [1, 2]
    assert Enum.map(data, & &1.score) == [4, 4]
  end