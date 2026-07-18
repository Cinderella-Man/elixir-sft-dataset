    property "works with Generators.user() as the inner generator" do
      check all(list <- Generators.non_empty_list(Generators.user())) do
        assert length(list) >= 1
        assert length(list) <= 20

        for user <- list do
          assert is_integer(user.id) and user.id > 0
          assert user.age >= 18
        end
      end
    end