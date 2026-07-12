    test "single-segment pattern does not match two-segment target" do
      roles = %{weird: ["posts"]}
      refute Rbac.permitted?([:weird], :posts, :read, roles)
    end