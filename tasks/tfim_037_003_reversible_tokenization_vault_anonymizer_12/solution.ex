    test "each field counts from 1 independently in its own namespace" do
      records = [
        %{email: "e1", ssn: "s1"},
        %{email: "e2", ssn: "s1"},
        %{email: "e1", ssn: "s2"}
      ]

      {[r1, r2, r3], _v} = Anonymizer.tokenize(records, [:email, :ssn])
      assert r1.email == "TOK_EMAIL_1"
      assert r1.ssn == "TOK_SSN_1"
      assert r2.email == "TOK_EMAIL_2"
      assert r2.ssn == "TOK_SSN_1"
      assert r3.email == "TOK_EMAIL_1"
      assert r3.ssn == "TOK_SSN_2"
    end