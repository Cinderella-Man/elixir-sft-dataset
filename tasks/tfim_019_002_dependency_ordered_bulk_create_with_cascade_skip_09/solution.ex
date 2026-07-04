  test "all-or-nothing detects cycles" do
    items = [
      %{"name" => "a", "ref" => "a", "parent" => "b"},
      %{"name" => "b", "ref" => "b", "parent" => "a"}
    ]

    assert {:error, results} = Catalog.bulk_create(items)
    assert Catalog.count() == 0
    assert {0, :error, :cycle} = Enum.find(results, fn {i, _, _} -> i == 0 end)
    assert {1, :error, :cycle} = Enum.find(results, fn {i, _, _} -> i == 1 end)
  end