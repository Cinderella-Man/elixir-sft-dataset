  test "orders by id ascending regardless of input order" do
    shuffled = Enum.shuffle(items(1..10))
    %{data: data} = CursorPaginator.paginate(shuffled, %{"limit" => "10"})
    assert Enum.map(data, & &1.id) == Enum.to_list(1..10)
  end