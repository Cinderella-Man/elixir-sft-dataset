    property ":name is a non-empty letters-only string of max 50 chars" do
      check all(user <- Generators.user()) do
        assert is_binary(user.name)
        assert String.length(user.name) >= 1
        assert String.length(user.name) <= 50
        assert String.match?(user.name, ~r/^[a-zA-Z]+$/)
      end
    end