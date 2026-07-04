  test "invalid on_conflict policy raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      Inventory.bulk_upsert([], on_conflict: :bogus)
    end
  end