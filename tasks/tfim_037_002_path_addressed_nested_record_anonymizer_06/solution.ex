    test "hashes a value at a nested path and leaves siblings alone" do
      records = [%{id: 1, user: %{email: "a@x.com", name: "Al"}}]
      [r] = Anonymizer.anonymize(records, %{"user.email" => :hash})
      assert r.user.email == sha256("a@x.com")
      assert r.user.name == "Al"
      assert r.id == 1
    end