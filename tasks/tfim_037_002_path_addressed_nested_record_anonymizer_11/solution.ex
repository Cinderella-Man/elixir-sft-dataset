    test "deterministic fake preserves referential integrity across nesting" do
      records = [%{a: %{name: "Bob"}, b: %{name: "Bob"}}]
      [r] = Anonymizer.anonymize(records, %{"a.name" => {:fake, "s"}, "b.name" => {:fake, "s"}})
      assert r.a.name == r.b.name
      assert r.a.name != "Bob"
      assert is_binary(r.a.name)
    end