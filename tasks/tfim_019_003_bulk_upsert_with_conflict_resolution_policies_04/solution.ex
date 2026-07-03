  test "all/0 reflects updates and stays deduplicated by sku" do
    seed("A", "Old", 10, 5)

    assert {:ok, [{0, :updated, _}]} =
             Inventory.bulk_upsert([%{"sku" => "A", "name" => "New", "price" => 20, "qty" => 3}],
               on_conflict: :merge
             )

    assert [record] = Inventory.all()
    assert record.sku == "A"
    assert record.name == "New"
    assert record.qty == 8
  end