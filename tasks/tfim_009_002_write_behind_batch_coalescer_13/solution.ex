  test "key is cleared after error, allowing a new batch", %{bc: bc} do
    assert {:error, :oops} =
             BatchCollector.submit(bc, :k, :item, fn _ -> {:error, :oops} end)

    assert {:ok, :recovered} =
             BatchCollector.submit(bc, :k, :item, fn _ -> {:ok, :recovered} end)
  end