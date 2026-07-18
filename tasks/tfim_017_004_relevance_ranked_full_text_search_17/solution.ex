  test "price sort defaults to ascending and breaks equal prices by id ascending" do
    assert {:ok, %{data: data}} = Ranked.search(products(), %{"sort" => "price"})

    # 1500(4), 2999(3), 2999(5) -> tie by id asc, 8999(1), 12999(2)
    assert ids(data) == [4, 3, 5, 1, 2]
  end