  test "selecting a tag shrinks the category facet" do
    assert {:ok, %{data: data, total: 3, facets: facets}} =
             Faceted.search(products(), %{"tags" => ["office"], "sort" => "id"})

    assert ids(data) == [3, 4, 5]
    # category facet excludes categories filter but the tag filter still applies
    assert facets.categories == %{"electronics" => 3}
    # tag facet excludes the tag filter -> full tag counts
    assert facets.tags["office"] == 3
    assert facets.tags["outdoor"] == 3
  end