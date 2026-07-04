  test "deletion_order/1 reports a cycle" do
    spec = %{"a" => ["b"], "b" => ["a"]}
    assert {:error, {:cycle, ["a", "b"]}} = DBCleaner.deletion_order(spec)
  end