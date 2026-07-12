    test "drops keys that are not in the schema (whitelist)" do
      params = %{"name" => "bob", "role" => "admin", "is_admin" => true}
      assert {:ok, out} = Sanitizer.sanitize(params, schema())
      assert out == %{"name" => "bob"}
      refute Map.has_key?(out, "role")
      refute Map.has_key?(out, "is_admin")
    end