  test "sort by category descending with id tie-break" do
    assert {:ok, %{data: data}} =
             Faceted.search(products(), %{"sort" => "category", "order" => "desc"})

    categories = Enum.map(data, & &1.category)
    assert categories == Enum.sort(categories, :desc)
  end