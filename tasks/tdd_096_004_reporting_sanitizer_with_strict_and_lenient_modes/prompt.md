# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule SanitizerTest do
  use ExUnit.Case, async: false

  describe "sql_identifier/2" do
    test "clean input has no violations in either mode" do
      assert {:ok, "users", []} = Sanitizer.sql_identifier("users")
      assert {:ok, "users", []} = Sanitizer.sql_identifier("users", mode: :strict)
    end

    test "lenient reports removed illegal chars" do
      assert {:ok, "users", [:removed_illegal_chars]} = Sanitizer.sql_identifier("us;ers")
    end

    test "lenient reports digit-start prefixing" do
      assert {:ok, "_1table", [:prefixed_digit_start]} = Sanitizer.sql_identifier("1table")
    end

    test "violations come in fixed order" do
      assert {:ok, "_1a", [:removed_illegal_chars, :prefixed_digit_start]} =
               Sanitizer.sql_identifier("1;a")
    end

    test "strict mode rejects dirty input" do
      assert {:error, [:removed_illegal_chars]} =
               Sanitizer.sql_identifier("us;ers", mode: :strict)
    end

    test "empty result is a hard error in both modes" do
      assert {:error, [:empty]} = Sanitizer.sql_identifier("!!!")
      assert {:error, [:empty]} = Sanitizer.sql_identifier("!!!", mode: :strict)
    end
  end

  describe "filename/2" do
    test "clean input has no violations" do
      assert {:ok, "report.pdf", []} = Sanitizer.filename("report.pdf")
    end

    test "reports null bytes" do
      assert {:ok, "file.txt", [:removed_null_bytes]} = Sanitizer.filename("file\0.txt")
    end

    test "reports traversal in fixed order" do
      assert {:ok, "etcpasswd", [:removed_path_separators, :collapsed_dots, :trimmed_dots]} =
               Sanitizer.filename("../etc/passwd")
    end

    test "reports illegal chars" do
      assert {:ok, "myfiledraft.docx", [:removed_illegal_chars]} =
               Sanitizer.filename("my file (draft).docx")
    end

    test "strict mode rejects dirty filenames" do
      assert {:error, [:removed_path_separators, :collapsed_dots, :trimmed_dots]} =
               Sanitizer.filename("../etc/passwd", mode: :strict)
    end

    test "empty result is a hard error" do
      assert {:error, [:empty]} = Sanitizer.filename("/\\")
      assert {:error, [:empty]} = Sanitizer.filename("", mode: :strict)
    end
  end

  describe "text/2" do
    test "clean text has no violations" do
      assert {:ok, "hello world", []} = Sanitizer.text("hello world")
    end

    test "escapes html and reports it" do
      assert {:ok, "&lt;b&gt;hi&lt;/b&gt;", [:escaped_html]} = Sanitizer.text("<b>hi</b>")
    end

    test "reports trimming and escaping in order" do
      assert {:ok, "&lt;x&gt;", [:trimmed_whitespace, :escaped_html]} =
               Sanitizer.text("  <x>  ")
    end

    test "reports removed control chars" do
      assert {:ok, "ab", [:removed_control_chars]} = Sanitizer.text("a\x01b")
    end

    test "strict mode rejects text needing escaping" do
      assert {:error, [:escaped_html]} = Sanitizer.text("a & b", mode: :strict)
    end

    test "empty text is valid (no hard failure)" do
      assert {:ok, "", []} = Sanitizer.text("")
      assert {:ok, "", [:trimmed_whitespace]} = Sanitizer.text("   ")
    end
  end

  test "text keeps tab, newline and carriage return untouched" do
    assert {:ok, "a\tb\nc\rd", []} = Sanitizer.text("a\tb\nc\rd")
    assert {:ok, "a\tb\nc\rd", []} = Sanitizer.text("a\tb\nc\rd", mode: :strict)
  end

  test "filename reports all five violations in the documented fixed order" do
    assert {:ok, "abc.d",
            [
              :removed_null_bytes,
              :removed_path_separators,
              :removed_illegal_chars,
              :collapsed_dots,
              :trimmed_dots
            ]} = Sanitizer.filename(".\0.a b/c..d.")
  end

  test "text reports control chars, trimming and escaping in fixed order" do
    assert {:ok, "&lt;a&gt;&amp;", [:removed_control_chars, :trimmed_whitespace, :escaped_html]} =
             Sanitizer.text("  \x01<a>&  ")
  end

  test "text escapes quotes and apostrophes without double-escaping ampersands" do
    assert {:ok, "He said &quot;hi&quot; &amp; it&#39;s fine", [:escaped_html]} =
             Sanitizer.text(~s(He said "hi" & it's fine))
  end

  test "clean filename and text succeed identically in strict mode" do
    assert {:ok, "report.pdf", []} = Sanitizer.filename("report.pdf", mode: :strict)
    assert {:ok, "report.pdf", []} = Sanitizer.filename("report.pdf", mode: :lenient)
    assert {:ok, "hello world", []} = Sanitizer.text("hello world", mode: :strict)
    assert {:ok, "hello world", []} = Sanitizer.text("hello world", mode: :lenient)
  end

  test "filename collapses runs at the exactly-two-dot boundary only" do
    assert {:ok, "a.b", []} = Sanitizer.filename("a.b")
    assert {:ok, "a.b", [:collapsed_dots]} = Sanitizer.filename("a..b")
    assert {:ok, "a.b", [:collapsed_dots]} = Sanitizer.filename("a...b")
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
