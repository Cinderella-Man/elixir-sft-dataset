    test "can read and update settings" do
      assert Permissions.can?(:admin, :settings, :read, @rules)
      assert Permissions.can?(:admin, :settings, :update, @rules)
    end