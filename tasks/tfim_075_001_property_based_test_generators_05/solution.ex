    property ":id is always a positive integer" do
      check all(user <- Generators.user()) do
        assert is_integer(user.id)
        assert user.id > 0
      end
    end