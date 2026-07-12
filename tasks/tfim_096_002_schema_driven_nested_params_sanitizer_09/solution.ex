    test "reports a bad integer at its path" do
      assert {:error, errors} =
               Sanitizer.sanitize(%{"age" => "not-a-num"}, %{"age" => :integer})

      assert errors[["age"]] == :not_an_integer
    end