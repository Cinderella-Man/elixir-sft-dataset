    test "cannot update settings" do
      refute Permissions.can?(:manager, :settings, :update, @rules)
    end