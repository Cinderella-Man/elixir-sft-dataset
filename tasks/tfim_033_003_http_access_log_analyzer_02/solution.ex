  test "requests_by_method counts are correct", %{report: r} do
    assert r.requests_by_method == %{
             "GET" => 6,
             "POST" => 1,
             "DELETE" => 1
           }
  end