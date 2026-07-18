  test "a code numerically below 100000 is still six characters wide", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")

    short =
      Enum.find_value(0..999, fn step ->
        {:ok, code} = TOTPVault.current_code(v, "alice", time: step * 30)
        if String.to_integer(code) < 100_000, do: code
      end)

    assert is_binary(short)
    assert byte_size(short) == 6
    assert String.match?(short, ~r/\A0\d{5}\z/)
  end