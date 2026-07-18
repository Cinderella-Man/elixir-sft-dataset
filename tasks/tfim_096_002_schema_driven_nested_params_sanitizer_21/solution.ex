  test "identifier and filename report not_a_string for non-binary values" do
    assert {:error, errors} =
             Sanitizer.sanitize(%{"table" => 7, "avatar" => ["x"]}, %{
               "table" => :identifier,
               "avatar" => :filename
             })

    assert errors[["table"]] == :not_a_string
    assert errors[["avatar"]] == :not_a_string
  end