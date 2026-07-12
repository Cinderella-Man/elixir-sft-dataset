    test "deny overrides a wildcard admin allow" do
      # admin :any/:any allows, but settings:delete deny wins
      assert AccessPolicy.authorized?(:admin, :settings, :read, @policies)
      refute AccessPolicy.authorized?(:admin, :settings, :delete, @policies)
    end