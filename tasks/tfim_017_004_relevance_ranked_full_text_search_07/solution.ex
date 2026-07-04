  test "absent query returns all products with score 0, name-ordered" do
    assert {:ok, %{data: data}} = Ranked.search(products(), %{})

    assert ids(data) == [4, 1, 2, 3, 5]
    assert Enum.all?(data, &(&1.score == 0))
  end