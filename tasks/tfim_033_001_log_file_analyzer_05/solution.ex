  test "top errors are sorted by frequency then alphabetically", %{report: r} do
    # db timeout: 3, disk full: 1, null pointer: 1
    # tie between "disk full" and "null pointer" broken alphabetically
    assert r.top_errors == [
             {"db timeout", 3},
             {"disk full", 1},
             {"null pointer", 1}
           ]
  end