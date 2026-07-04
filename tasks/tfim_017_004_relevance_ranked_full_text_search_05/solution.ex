  test "prefix matching tolerates partial query tokens" do
    assert {:ok, %{data: data}} = Ranked.search(products(), %{"q" => "work"})

    # p3 desc 'work' (1); p5 desc 'workouts' via prefix (1) -> tie, name asc
    assert ids(data) == [3, 5]
    assert Enum.map(data, & &1.score) == [1, 1]
  end