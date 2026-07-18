  test "descending sort breaks ties by id descending" do
    assert {:ok, %{data: data}} =
             Faceted.search(products(), %{"sort" => "category", "order" => "desc"})

    assert ids(data) == [2, 1, 6, 5, 4, 3]

    assert {:ok, %{data: asc}} = Faceted.search(products(), %{"sort" => "category"})
    assert ids(asc) == [3, 4, 5, 6, 1, 2]
  end