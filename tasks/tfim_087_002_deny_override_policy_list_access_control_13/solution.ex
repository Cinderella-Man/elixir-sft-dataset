    test "default deny with no statements" do
      assert AccessPolicy.evaluate(:admin, :posts, :read, []) == :deny
      refute AccessPolicy.authorized?(:admin, :posts, :read, [])
    end