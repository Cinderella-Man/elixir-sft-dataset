    test "deny overrides a would-be allow" do
      # editor delete: matched by deny statement, no allow -> deny
      refute AccessPolicy.authorized?(:editor, :posts, :delete, @policies)
    end