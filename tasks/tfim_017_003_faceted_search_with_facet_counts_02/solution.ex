  test "no params returns everything with full facet counts" do
    assert {:ok, %{data: data, facets: facets, total: 6}} = Faceted.search(products())

    assert length(data) == 6
    assert facets.categories == %{"footwear" => 2, "electronics" => 3, "fitness" => 1}

    assert facets.tags == %{
             "running" => 1,
             "outdoor" => 3,
             "formal" => 1,
             "wireless" => 1,
             "office" => 3,
             "wired" => 2,
             "home" => 1
           }
  end