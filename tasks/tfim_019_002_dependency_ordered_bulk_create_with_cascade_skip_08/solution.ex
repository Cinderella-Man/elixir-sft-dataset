  test "all-or-nothing reports unknown parent references" do
    items = [%{"name" => "x", "parent" => "nope"}]

    assert {:error, results} = Catalog.bulk_create(items)
    assert Catalog.count() == 0
    assert {0, :error, :unknown_parent} = hd(results)
  end