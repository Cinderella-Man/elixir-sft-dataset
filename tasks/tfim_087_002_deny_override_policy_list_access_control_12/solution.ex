    test "missing keys still respect deny precedence" do
      policies = [
        %{effect: :allow},
        %{effect: :deny, action: :delete}
      ]

      assert AccessPolicy.authorized?(:viewer, :posts, :read, policies)
      refute AccessPolicy.authorized?(:viewer, :posts, :delete, policies)
    end