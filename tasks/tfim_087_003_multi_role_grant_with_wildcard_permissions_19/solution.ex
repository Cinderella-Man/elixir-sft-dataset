  test "pattern with more than two segments never matches a two-segment target" do
    roles = %{odd: ["posts:read:extra", "*:*:*"]}
    refute Rbac.permitted?([:odd], :posts, :read, roles)
    refute Rbac.permitted?([:odd], :anything, :whatever, roles)
  end