    test "values that are not known tokens are left untouched" do
      {_t, vault} = Anonymizer.tokenize([%{email: "a@x.com"}], [:email])
      records = [%{email: "not-a-token", age: 30}]
      assert Anonymizer.detokenize(records, vault) == records
    end