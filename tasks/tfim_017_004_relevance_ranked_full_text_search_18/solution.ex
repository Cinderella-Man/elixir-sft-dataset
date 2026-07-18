  test "explicit name sort with desc order reverses alphabetical ordering" do
    assert {:ok, %{data: data}} =
             Ranked.search(products(), %{"sort" => "name", "order" => "desc"})

    assert ids(data) == [5, 3, 2, 1, 4]
  end