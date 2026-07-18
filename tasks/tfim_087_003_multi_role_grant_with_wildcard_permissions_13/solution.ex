    test "missing keys default to empty" do
      assert Rbac.effective_permissions(%{}, @roles) == MapSet.new()

      assert Rbac.effective_permissions(%{roles: [:viewer]}, @roles)
             |> MapSet.member?("posts:read")
    end