  test "metrics exposes all seven integer keys and reset zeroes every one of them" do
    {:ok, s} = Sanitizer.start_link(max_filename_length: 3)
    Sanitizer.sanitize_identifier(s, "@@@")
    Sanitizer.sanitize_identifier(s, "ok")
    Sanitizer.sanitize_filename(s, "abcdef")
    Sanitizer.sanitize_filename(s, "///")
    Sanitizer.strip_html(s, "<b>x</b>")

    keys = [
      :identifiers,
      :identifiers_blocked,
      :filenames,
      :filenames_blocked,
      :filenames_truncated,
      :tags_stripped,
      :html_calls
    ]

    m = Sanitizer.metrics(s)
    assert Enum.sort(Map.keys(m)) == Enum.sort(keys)
    assert Enum.all?(keys, fn k -> is_integer(Map.fetch!(m, k)) end)

    assert m == %{
             identifiers: 2,
             identifiers_blocked: 1,
             filenames: 2,
             filenames_blocked: 1,
             filenames_truncated: 1,
             tags_stripped: 2,
             html_calls: 1
           }

    assert :ok = Sanitizer.reset_metrics(s)
    assert Sanitizer.metrics(s) == Map.new(keys, fn k -> {k, 0} end)
  end