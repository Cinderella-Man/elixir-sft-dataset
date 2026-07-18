  test "key is cleared after a raised exception, allowing a fresh call", %{dd: dd} do
    assert {:error, {:exception, %RuntimeError{message: "boom"}}} =
             Dedup.execute(dd, "k", fn -> raise "boom" end)

    # The raise is a failure, so the key must be cleared for a fresh run.
    assert {:ok, :after_raise} = Dedup.execute(dd, "k", fn -> {:ok, :after_raise} end)
  end