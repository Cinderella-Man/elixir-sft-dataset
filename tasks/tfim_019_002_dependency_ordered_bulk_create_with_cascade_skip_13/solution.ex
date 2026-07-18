  test "all-or-nothing reports duplicate refs and rolls the batch back" do
    items = [
      %{"name" => "first", "ref" => "dup"},
      %{"name" => "second", "ref" => "dup"},
      %{"name" => "clean"}
    ]

    assert {:error, results} = Catalog.bulk_create(items)
    assert Catalog.count() == 0
    assert Catalog.all() == []

    assert {0, :error, :duplicate_ref} = Enum.find(results, fn {i, _, _} -> i == 0 end)
    assert {1, :error, :duplicate_ref} = Enum.find(results, fn {i, _, _} -> i == 1 end)
    assert {2, :ok, :valid} = Enum.find(results, fn {i, _, _} -> i == 2 end)
  end