  test "each version yields a distinct key set" do
    keys = fn v -> "/api/#{v}/users/1" |> call() |> json_body() |> Map.keys() |> Enum.sort() end

    assert keys.("v1") == ["email", "id", "name"]
    assert keys.("v2") == ["created_at", "email", "first_name", "id", "last_name"]
    assert keys.("v3") == ["country", "created_at", "email", "id", "name"]
  end