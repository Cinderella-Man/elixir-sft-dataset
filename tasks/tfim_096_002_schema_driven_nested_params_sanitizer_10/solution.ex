    test "reports nested identifier failure with full path" do
      params = %{"profile" => %{"handle" => "!!!"}}
      spec = %{"profile" => %{"handle" => :identifier}}
      assert {:error, errors} = Sanitizer.sanitize(params, spec)
      assert errors[["profile", "handle"]] == :empty
    end