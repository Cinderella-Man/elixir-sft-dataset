  test "deletion_order/1 breaks ties deterministically by name" do
    spec = %{"zebra" => [], "alpha" => [], "mango" => []}
    assert {:ok, ["alpha", "mango", "zebra"]} = DBCleaner.deletion_order(spec)
  end