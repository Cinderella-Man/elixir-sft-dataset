    test "missing path is ignored gracefully" do
      records = [%{user: %{name: "Alan"}}]
      [r] = Anonymizer.anonymize(records, %{"user.email" => :redact, "user.name" => :mask})
      assert r.user.name == "A**n"
      refute Map.has_key?(r.user, :email)
    end