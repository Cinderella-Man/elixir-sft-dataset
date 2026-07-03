  test "forward navigation with next_cursor does not repeat items and covers all" do
    all = items(1..12)

    page1 = CursorPaginator.paginate(all, %{"limit" => "5"})
    assert Enum.map(page1.data, & &1.id) == [1, 2, 3, 4, 5]
    assert page1.meta.has_next
    assert page1.meta.has_prev == false

    page2 =
      CursorPaginator.paginate(all, %{"limit" => "5", "cursor" => page1.meta.next_cursor})

    assert Enum.map(page2.data, & &1.id) == [6, 7, 8, 9, 10]
    assert page2.meta.has_next
    assert page2.meta.has_prev

    page3 =
      CursorPaginator.paginate(all, %{"limit" => "5", "cursor" => page2.meta.next_cursor})

    assert Enum.map(page3.data, & &1.id) == [11, 12]
    assert page3.meta.has_next == false
    assert page3.meta.next_cursor == nil
    assert page3.meta.has_prev == true
  end