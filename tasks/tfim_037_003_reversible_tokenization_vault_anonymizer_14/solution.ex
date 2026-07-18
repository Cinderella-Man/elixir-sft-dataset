    test "literal tokens restore to the value their counter position names" do
      records = [%{email: "a@x.com"}, %{email: "b@x.com"}]
      {_t, vault} = Anonymizer.tokenize(records, [:email])

      assert Anonymizer.detokenize([%{email: "TOK_EMAIL_1"}], vault) ==
               [%{email: "a@x.com"}]

      assert Anonymizer.detokenize([%{email: "TOK_EMAIL_2"}], vault) ==
               [%{email: "b@x.com"}]
    end