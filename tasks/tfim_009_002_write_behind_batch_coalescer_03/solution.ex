  test "flush_fn result is returned to caller", %{bc: bc} do
    assert {:ok, 42} =
             BatchCollector.submit(bc, :k, :ignored, fn _items -> {:ok, 42} end)
  end