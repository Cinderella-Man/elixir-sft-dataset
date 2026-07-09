  test "passes through {:error, reason} as-is when retries exhausted", %{rd: rd} do
    assert {:error, :permanent} =
             RetryDedup.execute(rd, "k", fn -> {:error, :permanent} end, max_retries: 0)
  end