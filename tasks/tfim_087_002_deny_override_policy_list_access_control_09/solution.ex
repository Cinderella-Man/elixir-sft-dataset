    test ":any roles matches every role" do
      for role <- [:viewer, :editor, :manager, :admin] do
        assert AccessPolicy.authorized?(role, :posts, :read, @policies),
               "expected #{role} to read posts via :any roles"
      end
    end