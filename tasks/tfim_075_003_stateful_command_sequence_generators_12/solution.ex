    property "produces both pushes and pops across many samples" do
      commands =
        Enum.flat_map(1..300, fn _ ->
          [cmds] = Enum.take(CommandGenerators.stack_program(), 1)
          cmds
        end)

      assert Enum.any?(commands, &match?({:push, _}, &1))
      assert :pop in commands
    end