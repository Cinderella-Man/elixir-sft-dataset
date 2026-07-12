    test "allows when a matching allow statement exists" do
      assert AccessPolicy.authorized?(:viewer, :posts, :read, @policies)
    end