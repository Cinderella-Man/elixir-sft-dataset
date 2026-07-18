    test "any error aborts the whole result (no partial ok)" do
      params = %{"name" => "ok", "age" => "bad"}
      assert {:error, _} = Sanitizer.sanitize(params, %{"name" => :text, "age" => :integer})
    end