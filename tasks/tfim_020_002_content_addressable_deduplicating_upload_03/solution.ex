  test "identical content under a new name dedupes (200, same id)", %{opts: opts} do
    content = "x,y\n1,2\n"
    c1 = call_upload(opts, "first.csv", content)
    c2 = call_upload(opts, "second.csv", content)

    assert c1.status == 201
    assert c2.status == 200

    b1 = json_body(c1)
    b2 = json_body(c2)

    assert b1["id"] == b2["id"]
    assert b1["deduplicated"] == false
    assert b2["deduplicated"] == true
    assert b1["upload_count"] == 1
    assert b2["upload_count"] == 2
    # original_name is preserved from the first upload
    assert b2["original_name"] == "first.csv"
  end