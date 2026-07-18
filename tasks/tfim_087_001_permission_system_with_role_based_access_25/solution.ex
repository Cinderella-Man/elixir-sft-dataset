    test "returns false for unknown resource" do
      refute Permissions.can?(:admin, :nonexistent, :read, @rules)
    end