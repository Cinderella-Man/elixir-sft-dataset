    test "collects multiple errors across the tree" do
      params = %{"age" => "x", "table" => "###"}
      spec = %{"age" => :integer, "table" => :identifier}
      assert {:error, errors} = Sanitizer.sanitize(params, spec)
      assert map_size(errors) == 2
      assert errors[["age"]] == :not_an_integer
      assert errors[["table"]] == :empty
    end