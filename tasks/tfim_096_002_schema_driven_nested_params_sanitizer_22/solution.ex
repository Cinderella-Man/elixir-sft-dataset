  test "list inner spec may itself be a nested schema map" do
    spec = %{"items" => {:list, %{"handle" => :identifier}}}

    assert {:ok, out} =
             Sanitizer.sanitize(%{"items" => [%{"handle" => "1a"}, %{"handle" => "b!"}]}, spec)

    assert out == %{"items" => [%{"handle" => "_1a"}, %{"handle" => "b"}]}

    assert {:error, errors} =
             Sanitizer.sanitize(%{"items" => [%{"handle" => "ok"}, "nope"]}, spec)

    assert errors[["items", 1]] == :expected_map
  end