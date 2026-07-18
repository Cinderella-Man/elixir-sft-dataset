  test "partial mode skips the dependent of a duplicate-ref item instead of erroring it" do
    items = [
      %{"name" => "one", "ref" => "dup"},
      %{"name" => "two", "ref" => "dup"},
      %{"name" => "child", "parent" => "dup"}
    ]

    assert {:ok, results} = Catalog.bulk_create(items, partial: true)

    assert {0, :error, :duplicate_ref} = Enum.find(results, fn {i, _, _} -> i == 0 end)
    assert {1, :error, :duplicate_ref} = Enum.find(results, fn {i, _, _} -> i == 1 end)
    assert {2, :skipped, ancestor} = Enum.find(results, fn {i, _, _} -> i == 2 end)
    assert ancestor in [0, 1]
    assert Catalog.count() == 0
  end