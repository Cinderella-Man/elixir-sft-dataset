  test "category and tag filters combine" do
    assert {:ok, %{data: data, total: 3, facets: facets}} =
             Faceted.search(products(), %{
               "categories" => ["electronics"],
               "tags" => ["office"],
               "sort" => "price"
             })

    assert ids(data) == [5, 3, 4]
    assert facets.categories == %{"electronics" => 3}
    assert facets.tags == %{"office" => 3, "wired" => 2, "wireless" => 1}
  end