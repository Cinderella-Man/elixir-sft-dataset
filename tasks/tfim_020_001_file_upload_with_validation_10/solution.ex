  test "accepts a file exactly at 5MB", %{opts: opts} do
    # Build a valid CSV that is just under 5MB
    header = "col1,col2\n"
    row = "aaaa,bbbb\n"
    # Fill up to just under 5MB
    num_rows = div(5_242_880 - byte_size(header), byte_size(row)) - 1
    content = header <> String.duplicate(row, num_rows)

    # Ensure we're within the limit
    assert byte_size(content) <= 5_242_880

    conn = call_upload(opts, "big_but_ok.csv", content)
    assert conn.status == 201
  end