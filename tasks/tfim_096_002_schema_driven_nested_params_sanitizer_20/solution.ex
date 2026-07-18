  test "text reports not_a_string for non-binary values" do
    assert {:error, errors} = Sanitizer.sanitize(%{"name" => 42}, %{"name" => :text})
    assert errors[["name"]] == :not_a_string

    assert {:error, nested} =
             Sanitizer.sanitize(%{"profile" => %{"bio" => :atom_value}}, %{
               "profile" => %{"bio" => :text}
             })

    assert nested[["profile", "bio"]] == :not_a_string
  end