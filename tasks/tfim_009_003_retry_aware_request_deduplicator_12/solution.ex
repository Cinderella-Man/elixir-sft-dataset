  test "key is cleared after final failure, allowing fresh execution", %{rd: rd} do
    assert {:error, :fail} =
             RetryDedup.execute(rd, "k", fn -> {:error, :fail} end, max_retries: 0)

    assert {:ok, :ok_now} = RetryDedup.execute(rd, "k", fn -> {:ok, :ok_now} end)
  end