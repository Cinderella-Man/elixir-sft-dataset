  test "skipped ancestor below a duplicate-ref item is the immediate skipped parent" do
    # 2 points at a duplicated-but-known ref, so it is skipped; 3 depends on 2
    # and must report 2 rather than either duplicate-ref declaring index.
    items = [
      %{"name" => "one", "ref" => "dup"},
      %{"name" => "two", "ref" => "dup"},
      %{"name" => "child", "ref" => "child", "parent" => "dup"},
      %{"name" => "grandchild", "parent" => "child"}
    ]

    assert {:ok, results} = Catalog.bulk_create(items, partial: true)

    assert {0, :error, :duplicate_ref} = Enum.find(results, fn {i, _, _} -> i == 0 end)
    assert {1, :error, :duplicate_ref} = Enum.find(results, fn {i, _, _} -> i == 1 end)
    assert {2, :skipped, ancestor} = Enum.find(results, fn {i, _, _} -> i == 2 end)
    assert ancestor in [0, 1]
    assert {3, :skipped, 2} = Enum.find(results, fn {i, _, _} -> i == 3 end)

    assert Catalog.count() == 0
    assert Catalog.all() == []
  end