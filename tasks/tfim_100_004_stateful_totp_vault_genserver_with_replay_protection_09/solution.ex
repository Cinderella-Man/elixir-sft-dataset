  test "consume rejects a wrong code as :invalid", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    {:ok, code} = TOTPVault.current_code(v, "alice", time: 90_000)

    wrong =
      code
      |> String.to_integer()
      |> then(&rem(&1 + 1, 1_000_000))
      |> Integer.to_string()
      |> String.pad_leading(6, "0")

    assert TOTPVault.consume(v, "alice", wrong, time: 90_000) == {:error, :invalid}
  end