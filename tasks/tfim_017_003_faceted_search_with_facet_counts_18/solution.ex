  test "empty result from a category selection keeps the full category facet source" do
    assert {:ok, %{data: [], total: 0, facets: facets}} =
             Faceted.search(products(), %{"categories" => ["nonexistent"]})

    assert facets.categories == %{"footwear" => 2, "electronics" => 3, "fitness" => 1}
    assert facets.tags == %{}
  end