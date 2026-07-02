  test "error result is returned to caller", %{bc: bc} do
    assert {:error, :boom} =
             BatchCollector.submit(bc, :k, :ignored, fn _items -> {:error, :boom} end)
  end