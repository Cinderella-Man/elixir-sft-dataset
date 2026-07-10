  test "stack_program/0 defaults to max_length 20: lengths stay in 0..20 and both endpoints occur" do
    Process.put(:stack_lengths, [])

    {:ok, _} =
      StreamData.check_all(
        CommandGenerators.stack_program(),
        [initial_seed: {11, 22, 33}, max_runs: 600],
        fn cmds ->
          Process.put(:stack_lengths, [length(cmds) | Process.get(:stack_lengths)])
          {:ok, cmds}
        end
      )

    lengths = Process.get(:stack_lengths)
    assert Enum.all?(lengths, &(&1 in 0..20))
    assert 0 in lengths, "the empty program (0 commands) was never generated"
    assert 20 in lengths, "the documented default maximum of 20 commands was never attained"
  end