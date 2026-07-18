    test "returns false for unknown action on known resource" do
      refute Permissions.can?(:admin, :posts, :nonexistent_action, @rules)
    end