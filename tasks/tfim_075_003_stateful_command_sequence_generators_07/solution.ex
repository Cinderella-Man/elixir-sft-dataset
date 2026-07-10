  test "withdraw stays available at the positive-balance boundary (balance exactly 1)" do
    # A positive balance is the documented precondition, so a withdrawal must be
    # possible when the modeled balance is exactly 1.
    Process.put(:withdraw_at_one, false)

    {:ok, _} =
      StreamData.check_all(
        CommandGenerators.account_program(),
        [initial_seed: {101, 102, 103}, max_runs: 4000],
        fn cmds ->
          Enum.reduce(cmds, 0, fn
            {:deposit, a}, bal ->
              bal + a

            {:withdraw, a}, bal ->
              if bal == 1, do: Process.put(:withdraw_at_one, true)
              bal - a
          end)

          {:ok, cmds}
        end
      )

    assert Process.get(:withdraw_at_one),
           "no :withdraw was ever generated at a modeled balance of exactly 1 " <>
             "across 4000 seeded samples"
  end