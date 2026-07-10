  test "max_length 0 is a valid argument and produces only the empty program" do
    stack_gen = CommandGenerators.stack_program(0)
    account_gen = CommandGenerators.account_program(0)

    assert match?(%StreamData{}, stack_gen)
    assert match?(%StreamData{}, account_gen)

    for {gen, seed} <- [{stack_gen, {1, 2, 3}}, {account_gen, {4, 5, 6}}] do
      {:ok, _} =
        StreamData.check_all(gen, [initial_seed: seed, max_runs: 50], fn cmds ->
          if cmds == [], do: {:ok, cmds}, else: {:error, cmds}
        end)
    end
  end