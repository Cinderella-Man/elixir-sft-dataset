  test "unparseable and blank price bounds are ignored rather than excluding products" do
    assert {:ok, %{data: data}} =
             Ranked.search(products(), %{"min_price" => "abc", "max_price" => "   "})

    assert Enum.sort(ids(data)) == [1, 2, 3, 4, 5]

    assert {:ok, %{data: partial}} =
             Ranked.search(products(), %{"min_price" => "2999abc", "max_price" => ""})

    assert Enum.sort(ids(partial)) == [1, 2, 3, 4, 5]
  end