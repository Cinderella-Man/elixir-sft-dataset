    test "editor can write posts" do
      assert Rbac.permitted?([:editor], :posts, :write, @roles)
    end