  test "multiple query tokens accumulate score" do
    assert {:ok, %{data: data}} = Ranked.search(products(), %{"q" => "running shoe"})

    # p1: name running(3)+shoes(3)=6, desc running(1)+shoes(1)=2 -> 8
    # p2: name 0, desc running(1)+shoe(1)=2 -> 2
    assert ids(data) == [1, 2]
    assert Enum.map(data, & &1.score) == [8, 2]
  end