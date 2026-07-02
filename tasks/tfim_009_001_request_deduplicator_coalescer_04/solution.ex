  test "passes through {:error, reason} as-is", %{dd: dd} do
    assert {:error, :boom} = Dedup.execute(dd, "k", fn -> {:error, :boom} end)
  end