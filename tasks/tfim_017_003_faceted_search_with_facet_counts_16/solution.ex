  test "empty tags list imposes no tag constraint" do
    assert {:ok, %{data: data, total: 6, facets: facets}} =
             Faceted.search(products(), %{"tags" => [], "sort" => "id"})

    assert ids(data) == [1, 2, 3, 4, 5, 6]
    assert facets.tags["office"] == 3
    assert facets.tags["outdoor"] == 3
  end