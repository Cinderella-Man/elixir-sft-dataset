    test "effective_permissions is the union set" do
      perms = Rbac.effective_permissions([:viewer, :editor], @roles)
      assert MapSet.member?(perms, "posts:write")
      assert MapSet.member?(perms, "comments:read")
    end