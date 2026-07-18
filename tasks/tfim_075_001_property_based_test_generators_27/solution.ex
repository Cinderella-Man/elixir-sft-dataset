    property "user generator can be filtered with StreamData.filter" do
      check all(user <- StreamData.filter(Generators.user(), &(&1.role == :admin))) do
        assert user.role == :admin
      end
    end