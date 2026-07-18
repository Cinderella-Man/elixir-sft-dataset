  test "empty categories list imposes no category constraint" do
    assert {:ok, %{data: data, total: 6, facets: facets}} =
             Faceted.search(products(), %{"categories" => [], "sort" => "id"})

    assert ids(data) == [1, 2, 3, 4, 5, 6]
    assert facets.categories == %{"footwear" => 2, "electronics" => 3, "fitness" => 1}
  end