  test "page below one falls back to the first page" do
    {:ok, %{data: zero_data, meta: zero}} =
      QueryPaginator.paginate(items(), %{"page" => "0", "page_size" => "2"})

    assert zero.current_page == 1
    assert Enum.map(zero_data, & &1.id) == [1, 2]

    {:ok, %{data: neg_data, meta: negative}} =
      QueryPaginator.paginate(items(), %{"page" => "-4", "page_size" => "2"})

    assert negative.current_page == 1
    assert Enum.map(neg_data, & &1.id) == [1, 2]
  end