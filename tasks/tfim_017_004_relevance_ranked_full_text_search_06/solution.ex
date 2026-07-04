  test "pre-filters apply before scoring" do
    assert {:ok, %{data: data}} =
             Ranked.search(products(), %{"q" => "run", "category" => "footwear"})

    assert Enum.sort(ids(data)) == [1, 2]

    assert {:ok, %{data: []}} =
             Ranked.search(products(), %{"q" => "run", "category" => "electronics"})
  end