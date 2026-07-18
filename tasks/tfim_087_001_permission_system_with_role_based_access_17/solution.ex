    test "can read settings" do
      assert Permissions.can?(:manager, :settings, :read, @rules)
    end