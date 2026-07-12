    property ":email is always a valid email-shaped string" do
      check all(user <- Generators.user()) do
        assert valid_email?(user.email)
      end
    end