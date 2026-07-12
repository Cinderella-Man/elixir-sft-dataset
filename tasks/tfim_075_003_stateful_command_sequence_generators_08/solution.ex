    property "always produces a valid stack program" do
      check all(cmds <- CommandGenerators.stack_program()) do
        assert is_list(cmds)
        assert stack_valid?(cmds)
      end
    end