    property "always produces a map with all required keys" do
      check all(user <- Generators.user()) do
        assert is_map(user)
        assert Map.has_key?(user, :id)
        assert Map.has_key?(user, :name)
        assert Map.has_key?(user, :email)
        assert Map.has_key?(user, :age)
        assert Map.has_key?(user, :role)
      end
    end