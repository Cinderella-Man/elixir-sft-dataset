  test "boolean rejects non-canonical values with not_a_boolean" do
    assert {:error, errors} =
             Sanitizer.sanitize(%{"active" => "TRUE"}, %{"active" => :boolean})

    assert errors[["active"]] == :not_a_boolean

    assert {:error, other} = Sanitizer.sanitize(%{"active" => 1}, %{"active" => :boolean})
    assert other[["active"]] == :not_a_boolean
  end