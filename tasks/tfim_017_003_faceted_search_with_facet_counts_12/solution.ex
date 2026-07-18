  test "empty result still reports facet source counts" do
    assert {:ok, %{data: [], total: 0, facets: facets}} =
             Faceted.search(products(), %{"name" => "nope_xyz"})

    assert facets.categories == %{}
    assert facets.tags == %{}
  end