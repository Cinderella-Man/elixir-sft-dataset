  test "withdrawals attain the documented lower endpoint 1 while the balance exceeds 1" do
    Process.put(:withdraw_amount_one, false)

    {:ok, _} =
      StreamData.check_all(
        CommandGenerators.account_program(),
        [initial_seed: {51, 52, 53}, max_runs: 3000],
        fn cmds ->
          Enum.reduce(cmds, 0, fn
            {:deposit, a}, bal ->
              bal + a

            {:withdraw, a}, bal ->
              if a == 1 and bal > 1, do: Process.put(:withdraw_amount_one, true)
              bal - a
          end)

          {:ok, cmds}
        end
      )

    assert Process.get(:withdraw_amount_one),
           "no :withdraw of the documented lower endpoint amount 1 was ever generated at a " <>
             "modeled balance greater than 1 across 3000 seeded samples"
  end