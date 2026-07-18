  test "accepts a CSV with a proper header row", %{opts: opts} do
    conn = call_upload(opts, "good.csv", "name,email\n")
    assert conn.status == 201
  end