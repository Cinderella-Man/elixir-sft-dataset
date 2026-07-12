    test "replaces listed fields with opaque tokens and returns a vault" do
      records = [%{id: 1, email: "a@x.com", name: "Al"}]
      {[r], vault} = Anonymizer.tokenize(records, [:email])
      assert r.id == 1
      assert r.name == "Al"
      assert is_binary(r.email)
      assert r.email != "a@x.com"
      assert r.email =~ ~r/^TOK_EMAIL_\d+$/
      assert is_map(vault)
    end