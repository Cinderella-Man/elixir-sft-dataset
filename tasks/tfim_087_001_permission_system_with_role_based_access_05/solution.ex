    test "cannot read settings" do
      refute Permissions.can?(:viewer, :settings, :read, @rules)
    end