  test "accepts a file exactly at 5MB", %{opts: opts} do
    # `:length` caps the WHOLE multipart request body, so size the CSV so that the
    # encoded body (boundary + part headers included) stays within the 5MB limit.
    # Aim ~1KB under to leave room for that framing overhead.
    header = "col1,col2\n"
    row = "aaaa,bbbb\n"
    target = 5_242_880 - 1024
    num_rows = div(target - byte_size(header), byte_size(row))
    content = header <> String.duplicate(row, num_rows)

    {body, content_type} = multipart_body("file", "big_but_ok.csv", content, "text/csv")

    # Document the reasoning: the constructed request body is within the limit, so
    # a 201 here is a genuine at-limit acceptance, not an accidental rejection.
    assert byte_size(body) <= 5_242_880

    conn = post_multipart(opts, body, content_type)
    assert conn.status == 201
  end