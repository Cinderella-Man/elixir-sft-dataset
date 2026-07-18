    property "always produces a valid account program (balance never negative)" do
      check all(cmds <- CommandGenerators.account_program()) do
        assert is_list(cmds)
        assert account_valid?(cmds)
      end
    end