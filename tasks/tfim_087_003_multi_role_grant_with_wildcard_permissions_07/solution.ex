    test "admin *:* matches everything" do
      assert Rbac.permitted?([:admin], :posts, :read, @roles)
      assert Rbac.permitted?([:admin], :settings, :destroy, @roles)
      assert Rbac.permitted?([:admin], :anything, :whatever, @roles)
    end