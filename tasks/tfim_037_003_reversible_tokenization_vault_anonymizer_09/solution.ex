    test "detokenize with an empty record list returns empty list" do
      {_t, vault} = Anonymizer.tokenize([%{email: "a@x.com"}], [:email])
      assert Anonymizer.detokenize([], vault) == []
    end