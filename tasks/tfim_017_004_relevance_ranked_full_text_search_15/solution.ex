  test "a single query token accumulates once per matching document token" do
    assert {:ok, %{data: data}} = Ranked.search(products(), %{"q" => "r"})

    # p2: name runner(3) + desc running(1)+rugged(1) = 5
    # p4: name rest(3) + desc rest(1) = 4
    # p1: name running(3) + desc running(1) = 4  -> tie with p4, name asc
    assert ids(data) == [2, 4, 1]
    assert Enum.map(data, & &1.score) == [5, 4, 4]
  end