  test "rows inserted and deleted between requests neither skip nor duplicate the next window" do
    page1 = CursorPaginator.paginate(items(1..10), %{"limit" => "3"})
    assert Enum.map(page1.data, & &1.id) == [1, 2, 3]

    mutated =
      items(1..10)
      |> Enum.reject(&(&1.id == 2))
      |> then(&[%{id: 0, name: "Item 0"} | &1])
      |> Enum.shuffle()

    page2 =
      CursorPaginator.paginate(mutated, %{"limit" => "3", "cursor" => page1.meta.next_cursor})

    assert Enum.map(page2.data, & &1.id) == [4, 5, 6]
  end