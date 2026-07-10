  test "deposit amounts respect the documented 1..1000 range and attain both endpoints" do
    Process.put(:deposit_amounts, [])

    {:ok, _} =
      StreamData.check_all(
        CommandGenerators.account_program(),
        [initial_seed: {7, 8, 9}, max_runs: 1500],
        fn cmds ->
          amounts = for {:deposit, a} <- cmds, do: a
          Process.put(:deposit_amounts, amounts ++ Process.get(:deposit_amounts))
          {:ok, cmds}
        end
      )

    amounts = Process.get(:deposit_amounts)
    assert amounts != []
    assert Enum.all?(amounts, &(&1 in 1..1000))
    assert 1 in amounts, "the deposit lower endpoint 1 was never generated"
    assert 1000 in amounts, "the deposit upper endpoint 1000 was never generated"
  end