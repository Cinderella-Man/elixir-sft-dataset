  test "meta never exposes total_count or total_pages on any page" do
    all = items(1..12)

    page1 = CursorPaginator.paginate(all, %{"limit" => "5"})
    page2 = CursorPaginator.paginate(all, %{"limit" => "5", "cursor" => page1.meta.next_cursor})
    empty = CursorPaginator.paginate([])

    for %{meta: meta} <- [page1, page2, empty] do
      refute Map.has_key?(meta, :total_count)
      refute Map.has_key?(meta, :total_pages)

      assert Map.keys(meta) |> Enum.sort() ==
               [:has_next, :has_prev, :next_cursor, :page_size, :prev_cursor]
    end
  end