  test "name matches outrank description-only matches" do
    assert {:ok, %{data: data}} = Ranked.search(products(), %{"q" => "trail"})

    # p2: name 'trail' (3) + desc 'trails' (1) = 4 ; p1: desc 'trail' (1) = 1
    assert ids(data) == [2, 1]
    assert Enum.map(data, & &1.score) == [4, 1]
  end