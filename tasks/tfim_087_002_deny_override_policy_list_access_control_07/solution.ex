    test "order of statements does not matter" do
      reversed = Enum.reverse(@policies)

      assert AccessPolicy.evaluate(:admin, :settings, :delete, @policies) ==
               AccessPolicy.evaluate(:admin, :settings, :delete, reversed)

      assert AccessPolicy.evaluate(:admin, :settings, :delete, reversed) == :deny
    end