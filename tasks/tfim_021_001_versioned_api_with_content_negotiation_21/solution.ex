  test "unmatched route returns 404" do
    conn = call(:get, "/api/nonexistent")

    assert conn.status == 404
  end