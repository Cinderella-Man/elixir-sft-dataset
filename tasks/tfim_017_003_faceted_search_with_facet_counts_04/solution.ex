  test "category facet ignores the category selection but tag facet reflects it" do
    assert {:ok, %{facets: facets}} =
             Faceted.search(products(), %{"categories" => ["footwear", "fitness"]})

    # category facet excludes its own filter -> counts over the full set
    assert facets.categories == %{"footwear" => 2, "electronics" => 3, "fitness" => 1}
    # tag facet still has the category filter applied -> only 1,2,6
    assert facets.tags == %{"outdoor" => 3, "running" => 1, "formal" => 1, "home" => 1}
  end