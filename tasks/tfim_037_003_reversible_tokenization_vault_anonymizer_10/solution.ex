    test "counter starts at 1 and increments by 1 per newly seen value" do
      records = [%{email: "a@x.com"}, %{email: "b@x.com"}, %{email: "c@x.com"}]
      {[r1, r2, r3], _v} = Anonymizer.tokenize(records, [:email])
      assert r1.email == "TOK_EMAIL_1"
      assert r2.email == "TOK_EMAIL_2"
      assert r3.email == "TOK_EMAIL_3"
    end