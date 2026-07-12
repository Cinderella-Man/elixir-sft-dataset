    test "referential integrity: same value maps to same token" do
      records = [%{email: "a@x.com"}, %{email: "a@x.com"}, %{email: "b@x.com"}]
      {[r1, r2, r3], _v} = Anonymizer.tokenize(records, [:email])
      assert r1.email == r2.email
      refute r1.email == r3.email
    end