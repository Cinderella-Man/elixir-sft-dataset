  test "name_contains is case-insensitive" do
    {:ok, %{data: data, meta: meta}} =
      QueryPaginator.paginate(items(), %{"name_contains" => "A"})

    names = Enum.map(data, & &1.name)
    assert "Alice" in names
    assert "Carol" in names
    assert "amanda" in names
    assert "dave" in names
    assert meta.total_count == length(data)
    assert meta.filters.name_contains == "A"
  end