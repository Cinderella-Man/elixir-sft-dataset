    property "programs can be filtered to a minimum length without breaking validity" do
      gen = StreamData.filter(CommandGenerators.stack_program(), &(length(&1) >= 1))

      check all(cmds <- gen) do
        assert length(cmds) >= 1
        assert stack_valid?(cmds)
      end
    end