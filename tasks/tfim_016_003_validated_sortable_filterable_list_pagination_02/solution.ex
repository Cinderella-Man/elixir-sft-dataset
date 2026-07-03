  test "defaults sort by id ascending with default paging" do
    assert {:ok, %{data: data, meta: meta}} = QueryPaginator.paginate(items())
    assert Enum.map(data, & &1.id) == [1, 2, 3, 4, 5, 6]
    assert meta.current_page == 1
    assert meta.page_size == 20
    assert meta.total_count == 6
    assert meta.total_pages == 1
    assert meta.sort == :id
    assert meta.order == :asc
    assert meta.filters == %{min_age: nil, max_age: nil, name_contains: nil}
  end