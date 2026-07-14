    test "counter advances only on first sight of a value, not on repeats" do
      records = [
        %{email: "a@x.com"},
        %{email: "a@x.com"},
        %{email: "b@x.com"},
        %{email: "a@x.com"},
        %{email: "c@x.com"}
      ]

      {[r1, r2, r3, r4, r5], _v} = Anonymizer.tokenize(records, [:email])
      assert r1.email == "TOK_EMAIL_1"
      assert r2.email == "TOK_EMAIL_1"
      assert r3.email == "TOK_EMAIL_2"
      assert r4.email == "TOK_EMAIL_1"
      assert r5.email == "TOK_EMAIL_3"
    end