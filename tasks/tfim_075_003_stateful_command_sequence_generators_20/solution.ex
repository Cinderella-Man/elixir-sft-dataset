  test "withdrawals attain the documented upper endpoint: the whole modeled balance" do
    Process.put(:withdraw_full_balance, false)

    {:ok, _} =
      StreamData.check_all(
        CommandGenerators.account_program(),
        [initial_seed: {201, 202, 203}, max_runs: 3000],
        fn cmds ->
          Enum.reduce(cmds, 0, fn
            {:deposit, a}, bal ->
              bal + a

            {:withdraw, a}, bal ->
              if a == bal and bal > 1, do: Process.put(:withdraw_full_balance, true)
              bal - a
          end)

          {:ok, cmds}
        end
      )

    assert Process.get(:withdraw_full_balance),
           "no :withdraw ever drew the documented upper endpoint of its 1..current_balance " <>
             "range (amount == modeled balance > 1) across 3000 seeded samples"
  end