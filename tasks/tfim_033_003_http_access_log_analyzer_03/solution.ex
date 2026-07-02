  test "requests_by_status counts are correct", %{report: r} do
    assert r.requests_by_status == %{
             200 => 4,
             201 => 1,
             204 => 1,
             404 => 1,
             500 => 1
           }
  end