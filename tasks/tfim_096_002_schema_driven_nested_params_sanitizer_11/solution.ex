    test "reports list element failure with integer index in path" do
      params = %{"scores" => ["1", "oops", "3"]}
      spec = %{"scores" => {:list, :integer}}
      assert {:error, errors} = Sanitizer.sanitize(params, spec)
      assert errors[["scores", 1]] == :not_an_integer
      refute Map.has_key?(errors, ["scores", 0])
    end