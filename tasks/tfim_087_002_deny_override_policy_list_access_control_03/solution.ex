    test "default-denies when nothing matches" do
      refute AccessPolicy.authorized?(:viewer, :posts, :write, @policies)
      assert AccessPolicy.evaluate(:viewer, :posts, :write, @policies) == :deny
    end