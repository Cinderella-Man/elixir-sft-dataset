    property ":age is always between 18 and 120" do
      check all(user <- Generators.user()) do
        assert user.age >= 18
        assert user.age <= 120
      end
    end