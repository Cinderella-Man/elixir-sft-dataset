    test "cannot read settings" do
      refute Permissions.can?(:editor, :settings, :read, @rules)
    end