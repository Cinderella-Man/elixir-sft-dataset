    property ":role is always one of the allowed atoms" do
      check all(user <- Generators.user()) do
        assert user.role in [:admin, :editor, :viewer]
      end
    end