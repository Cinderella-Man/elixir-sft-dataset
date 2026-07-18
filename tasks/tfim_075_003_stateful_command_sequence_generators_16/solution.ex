    property "no withdrawal ever exceeds the modeled balance at that point" do
      check all(cmds <- CommandGenerators.account_program()) do
        Enum.reduce(cmds, 0, fn
          {:deposit, a}, bal ->
            bal + a

          {:withdraw, a}, bal ->
            assert a <= bal
            bal - a
        end)
      end
    end