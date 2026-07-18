  test "window: 3 near the epoch still refuses a code from a step below zero", %{vault: v} do
    # At time 0 the base step is 0, so a window of 3 spans steps 0..3 only:
    # negative steps are never considered, however far the window reaches back.
    n =
      Enum.find(1..5, fn n ->
        {:ok, secret} = TOTPVault.register(v, "clamp#{n}")
        in_window = for step <- 0..3, do: rfc6238_code(secret, step * 30)
        rfc6238_code(secret, -30) not in in_window
      end)

    account = "clamp#{n}"
    {:ok, secret} = TOTPVault.secret(v, account)
    below_epoch = rfc6238_code(secret, -30)

    result = TOTPVault.consume(v, account, below_epoch, time: 0, window: 3)
    assert result == {:error, :invalid}
  end