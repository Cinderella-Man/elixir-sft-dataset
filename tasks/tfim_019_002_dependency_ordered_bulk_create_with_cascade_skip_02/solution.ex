  test "creates all items when every item is valid with no dependencies" do
    items = [%{"name" => "Alpha"}, %{"name" => "Beta"}, %{"name" => "Gamma"}]

    assert {:ok, results} = Catalog.bulk_create(items)
    assert length(results) == 3
    assert Catalog.count() == 3

    for {i, expected} <- Enum.with_index(["Alpha", "Beta", "Gamma"]) |> Enum.map(fn {n, i} -> {i, n} end) do
      it = item(results, i)
      assert it.name == expected
      assert is_integer(it.id)
      assert it.parent_id == nil
    end
  end