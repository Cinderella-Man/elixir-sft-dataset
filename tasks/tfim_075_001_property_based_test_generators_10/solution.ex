    property "produces diverse roles across many samples" do
      roles =
        Enum.map(1..300, fn _ ->
          [user] = Enum.take(Generators.user(), 1)
          user.role
        end)

      assert :admin in roles
      assert :editor in roles
      assert :viewer in roles
    end