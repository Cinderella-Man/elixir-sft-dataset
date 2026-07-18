  test "an integer code whose string form has a leading zero is accepted", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")

    # A code below 100_000 loses its leading zero when handed over as an
    # integer; the integer form must still match the padded code.
    found =
      Enum.find_value(0..999, fn step ->
        {:ok, code} = TOTPVault.current_code(v, "alice", time: step * 30)
        if String.starts_with?(code, "0"), do: {step, code}
      end)

    assert {step, code} = found
    assert TOTPVault.consume(v, "alice", String.to_integer(code), time: step * 30) == :ok
  end