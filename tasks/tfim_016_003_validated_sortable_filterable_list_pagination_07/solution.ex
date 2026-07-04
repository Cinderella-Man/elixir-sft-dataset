  test "min_age and max_age filters affect total_count and pages" do
    {:ok, %{data: data, meta: meta}} =
      QueryPaginator.paginate(items(), %{"min_age" => "25", "max_age" => "35", "page_size" => "2"})

    assert meta.total_count == 4
    assert meta.total_pages == 2
    assert length(data) == 2
    assert Enum.all?(data, &(&1.age >= 25 and &1.age <= 35))
  end