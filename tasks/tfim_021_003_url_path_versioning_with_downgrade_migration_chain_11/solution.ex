  test "all responses are application/json" do
    for path <- ["/api/v1/users/1", "/api/v2/users/999", "/api/v9/users/1"] do
      assert content_type(call(path)) =~ "application/json"
    end
  end