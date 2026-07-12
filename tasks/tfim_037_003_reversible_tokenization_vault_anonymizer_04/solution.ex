    test "distinct fields get distinct token namespaces even for equal values" do
      records = [%{email: "same", user: "same"}]
      {[r], _v} = Anonymizer.tokenize(records, [:email, :user])
      refute r.email == r.user
      assert r.email =~ ~r/^TOK_EMAIL_/
      assert r.user =~ ~r/^TOK_USER_/
    end