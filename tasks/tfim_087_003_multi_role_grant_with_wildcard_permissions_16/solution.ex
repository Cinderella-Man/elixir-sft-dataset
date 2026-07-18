  test "overlapping role patterns are unioned without duplicates" do
    assert Rbac.effective_permissions([:viewer, :editor], @roles) ==
             MapSet.new([
               "posts:read",
               "posts:write",
               "comments:read",
               "comments:write"
             ])
  end