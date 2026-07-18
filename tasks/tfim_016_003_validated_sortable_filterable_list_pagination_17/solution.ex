  test "min_age and max_age are inclusive at exactly-equal boundary values" do
    {:ok, %{data: data, meta: meta}} =
      QueryPaginator.paginate(items(), %{"min_age" => "25", "max_age" => "25"})

    assert Enum.map(data, & &1.id) == [2, 4]
    assert meta.total_count == 2
    assert meta.total_pages == 1

    {:ok, %{data: single}} =
      QueryPaginator.paginate(items(), %{"min_age" => "22", "max_age" => "22"})

    assert Enum.map(single, & &1.id) == [6]
  end