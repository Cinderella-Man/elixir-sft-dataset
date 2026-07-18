  test "the unmatched-route response is also json encoded" do
    conn = call("/api/v1/widgets/1")

    assert content_type(conn) =~ "application/json"
    assert json_body(conn) == %{"error" => "not found"}
  end