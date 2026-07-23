# The tests are the spec

Below is a complete, self-contained ExUnit suite. It is the only
specification you get: build the module (or modules) it exercises until
every test passes. Reach for nothing beyond what the tests themselves
require — the standard library and OTP unless the suite says otherwise.
House style applies (`@moduledoc`, `@doc` + `@spec` on the public API,
no compiler warnings).

## The test suite

```elixir
defmodule SanitizerTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = Sanitizer.start_link()
    {:ok, server: pid}
  end

  describe "identifier sanitization + metrics" do
    test "cleans and counts", %{server: s} do
      assert {:ok, "users"} = Sanitizer.sanitize_identifier(s, "us;ers")
      assert {:ok, "_1t"} = Sanitizer.sanitize_identifier(s, "1t")
      assert {:error, :empty} = Sanitizer.sanitize_identifier(s, "!!!")

      m = Sanitizer.metrics(s)
      assert m.identifiers == 3
      assert m.identifiers_blocked == 1
    end
  end

  describe "filename sanitization + metrics" do
    test "cleans traversal and counts", %{server: s} do
      assert {:ok, "etcpasswd"} = Sanitizer.sanitize_filename(s, "../etc/passwd")
      assert {:error, :empty} = Sanitizer.sanitize_filename(s, "/\\")

      m = Sanitizer.metrics(s)
      assert m.filenames == 2
      assert m.filenames_blocked == 1
      assert m.filenames_truncated == 0
    end

    test "truncates to max_filename_length and counts truncations" do
      {:ok, s} = Sanitizer.start_link(max_filename_length: 5)
      assert {:ok, "abcde"} = Sanitizer.sanitize_filename(s, "abcdefghij")
      assert {:ok, "xy"} = Sanitizer.sanitize_filename(s, "xy")

      m = Sanitizer.metrics(s)
      assert m.filenames == 2
      assert m.filenames_truncated == 1
    end
  end

  describe "html stripping + metrics" do
    test "removes script content and counts tags", %{server: s} do
      assert {:ok, "Hello world", n} =
               Sanitizer.strip_html(s, "<b>Hello</b> <script>alert(1)</script>world")

      # <b>, </b>, <script>, </script> = 4 tag tokens in the original
      assert n == 4

      assert {:ok, "plain", _} = Sanitizer.strip_html(s, "<div><p>plain</p></div>")

      m = Sanitizer.metrics(s)
      assert m.html_calls == 2
      assert m.tags_stripped == 4 + 4
    end

    test "no tags means zero stripped", %{server: s} do
      assert {:ok, "just text", 0} = Sanitizer.strip_html(s, "just text")
    end
  end

  describe "reset_metrics" do
    test "zeroes everything", %{server: s} do
      Sanitizer.sanitize_identifier(s, "ok")
      Sanitizer.strip_html(s, "<b>x</b>")
      assert :ok = Sanitizer.reset_metrics(s)

      m = Sanitizer.metrics(s)
      assert m.identifiers == 0
      assert m.tags_stripped == 0
      assert m.html_calls == 0
    end
  end

  describe "concurrency" do
    test "metrics stay exact under many concurrent callers", %{server: s} do
      valid =
        for _ <- 1..100 do
          Task.async(fn -> Sanitizer.sanitize_identifier(s, "users") end)
        end

      invalid =
        for _ <- 1..50 do
          Task.async(fn -> Sanitizer.sanitize_identifier(s, "###") end)
        end

      files =
        for _ <- 1..40 do
          Task.async(fn -> Sanitizer.sanitize_filename(s, "../a/b") end)
        end

      Enum.each(valid ++ invalid ++ files, &Task.await/1)

      m = Sanitizer.metrics(s)
      assert m.identifiers == 150
      assert m.identifiers_blocked == 50
      assert m.filenames == 40
      assert m.filenames_blocked == 0
    end
  end

  test "default max_filename_length truncates to 255 and counts the truncation", %{server: s} do
    long = String.duplicate("a", 300)
    assert {:ok, cleaned} = Sanitizer.sanitize_filename(s, long)
    assert cleaned == String.duplicate("a", 255)
    assert String.length(cleaned) == 255

    m = Sanitizer.metrics(s)
    assert m.filenames == 1
    assert m.filenames_truncated == 1
  end

  test "filename of exactly max_filename_length is kept whole and not counted truncated" do
    {:ok, s} = Sanitizer.start_link(max_filename_length: 5)
    assert {:ok, "abcde"} = Sanitizer.sanitize_filename(s, "abcde")

    m = Sanitizer.metrics(s)
    assert m.filenames == 1
    assert m.filenames_truncated == 0
  end

  test "script and style blocks are dropped case-insensitively across newlines", %{server: s} do
    input = "a<STYLE>\n.x { color: red; }\n</StYlE>b<ScRiPt>\nalert(1)\n</SCRIPT>c<i>d</i>"

    assert {:ok, cleaned, n} = Sanitizer.strip_html(s, input)
    assert cleaned == "abcd"
    assert n == 6

    m = Sanitizer.metrics(s)
    assert m.html_calls == 1
    assert m.tags_stripped == 6
  end

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

  test "server started with :name is reachable through the public API by that name" do
    name = :sanitizer_named_server_audit
    assert {:ok, pid} = Sanitizer.start_link(name: name, max_filename_length: 4)
    assert Process.whereis(name) == pid

    assert {:ok, "_9x"} = Sanitizer.sanitize_identifier(name, "9x!")
    assert {:ok, "abcd"} = Sanitizer.sanitize_filename(name, "abcdefg")

    m = Sanitizer.metrics(name)
    assert m.identifiers == 1
    assert m.filenames == 1
    assert m.filenames_truncated == 1

    assert :ok = Sanitizer.reset_metrics(name)
    assert Sanitizer.metrics(name).identifiers == 0
  end
end
```

Send back the implementation only — one file, no tests.
