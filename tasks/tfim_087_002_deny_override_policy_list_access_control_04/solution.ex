    test "list membership in roles field" do
      assert AccessPolicy.authorized?(:editor, :posts, :write, @policies)
      assert AccessPolicy.authorized?(:admin, :posts, :write, @policies)
    end