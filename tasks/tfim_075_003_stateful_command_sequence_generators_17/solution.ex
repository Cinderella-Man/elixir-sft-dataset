    property "produces both deposits and withdrawals across many samples" do
      commands =
        Enum.flat_map(1..300, fn _ ->
          [cmds] = Enum.take(CommandGenerators.account_program(), 1)
          cmds
        end)

      assert Enum.any?(commands, &match?({:deposit, _}, &1))
      assert Enum.any?(commands, &match?({:withdraw, _}, &1))
    end