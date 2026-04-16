defmodule SanitizerTest do
  use ExUnit.Case, async: true

  # -------------------------------------------------------
  # Sanitizer.html/2 — tag stripping
  # -------------------------------------------------------

  describe "Sanitizer.html/1 with default allowlist" do
    test "passes through allowed tags untouched" do
      assert Sanitizer.html("<b>bold</b>") == "<b>bold</b>"
      assert Sanitizer.html("<i>italic</i>") == "<i>italic</i>"
      assert Sanitizer.html("<em>em</em>") == "<em>em</em>"
      assert Sanitizer.html("<strong>strong</strong>") == "<strong>strong</strong>"
    end

    test "strips disallowed tags but keeps their text" do
      # NOTE: <script> is a raw-content tag — its inner text is also discarded.
      assert Sanitizer.html("<script>alert(1)</script>") == ""
      assert Sanitizer.html("<div>hello</div>") == "hello"
      assert Sanitizer.html("<p>paragraph</p>") == "paragraph"
      assert Sanitizer.html("<span>text</span>") == "text"
    end

    test "strips all attributes from allowed tags (except href on <a>)" do
      assert Sanitizer.html(~s[<b class="evil">text</b>]) == "<b>text</b>"
      assert Sanitizer.html(~s[<i style="color:red">text</i>]) == "<i>text</i>"
    end

    test "preserves href attribute on <a> tags" do
      assert Sanitizer.html(~s[<a href="https://example.com">link</a>]) ==
               ~s[<a href="https://example.com">link</a>]
    end

    test "strips non-href attributes from <a> tags" do
      assert Sanitizer.html(~s[<a href="https://x.com" onclick="evil()">link</a>]) ==
               ~s[<a href="https://x.com">link</a>]
    end

    test "rejects javascript: URLs — strips the tag, keeps text" do
      assert Sanitizer.html(~s[<a href="javascript:alert(1)">click</a>]) == "click"
    end

    test "rejects javascript: URLs case-insensitively" do
      assert Sanitizer.html(~s[<a href="JavaScript:alert(1)">click</a>]) == "click"
      assert Sanitizer.html(~s[<a href="JAVASCRIPT:alert(1)">click</a>]) == "click"
    end

    test "rejects javascript: URLs with leading whitespace" do
      assert Sanitizer.html(~s[<a href="  javascript:alert(1)">click</a>]) == "click"
    end

    test "strips nested disallowed tags, preserving text" do
      assert Sanitizer.html("<div><b>bold</b> and plain</div>") == "<b>bold</b> and plain"
    end

    test "handles plain text with no tags" do
      assert Sanitizer.html("hello world") == "hello world"
    end

    test "handles empty string" do
      assert Sanitizer.html("") == ""
    end

    test "classic XSS vector is neutralised" do
      input = ~s[<img src=x onerror="alert('XSS')">]
      refute Sanitizer.html(input) =~ "onerror"
      refute Sanitizer.html(input) =~ "alert"
    end
  end

  describe "Sanitizer.html/2 with custom allowlist" do
    test "respects custom :allow option" do
      result = Sanitizer.html("<span>hello</span><b>world</b>", allow: ["span"])
      # <span> is in the allowlist so its tag is preserved; <b> is not, so only
      # its text content survives.
      assert result == "<span>hello</span>world"
      refute result =~ "<b>"
    end
  end

  # -------------------------------------------------------
  # Sanitizer.sql_identifier/1
  # -------------------------------------------------------

  describe "Sanitizer.sql_identifier/1" do
    test "allows alphanumeric and underscore" do
      assert {:ok, "users"} = Sanitizer.sql_identifier("users")
      assert {:ok, "user_name"} = Sanitizer.sql_identifier("user_name")
      assert {:ok, "col1"} = Sanitizer.sql_identifier("col1")
    end

    test "strips dangerous characters" do
      assert {:ok, "users"} = Sanitizer.sql_identifier("us;ers")
      assert {:ok, "tablename"} = Sanitizer.sql_identifier("table--name")
      # Quotes, spaces, and = are stripped; letters and digits survive → "colOR11"
      assert {:ok, "colOR11"} = Sanitizer.sql_identifier("col' OR '1'='1")
    end

    test "returns error for empty result after stripping" do
      assert {:error, :empty} = Sanitizer.sql_identifier(";;;")
      assert {:error, :empty} = Sanitizer.sql_identifier("")
      assert {:error, :empty} = Sanitizer.sql_identifier("---")
    end

    test "prepends underscore when result starts with a digit" do
      assert {:ok, "_1table"} = Sanitizer.sql_identifier("1table")
      assert {:ok, "_99problems"} = Sanitizer.sql_identifier("99problems")
    end

    test "passes through already-safe identifiers unchanged" do
      assert {:ok, "Orders"} = Sanitizer.sql_identifier("Orders")
    end
  end

  # -------------------------------------------------------
  # Sanitizer.filename/1
  # -------------------------------------------------------

  describe "Sanitizer.filename/1" do
    test "allows safe filenames unchanged" do
      assert {:ok, "report.pdf"} = Sanitizer.filename("report.pdf")
      assert {:ok, "my_file-2024.txt"} = Sanitizer.filename("my_file-2024.txt")
    end

    test "strips null bytes" do
      assert {:ok, "file.txt"} = Sanitizer.filename("file\0.txt")
    end

    test "strips path traversal sequences" do
      # Slashes are stripped (not converted to dots), so "etc" and "passwd" are
      # joined directly; strip_dots_ok has no dots to convert → "etcpasswd"
      assert {:ok, "etcpasswd"} = Sanitizer.filename("../etc/passwd") |> strip_dots_ok()
      # The exact result may vary but must not contain .. or /
      {:ok, result} = Sanitizer.filename("../../secret.txt")
      refute result =~ ".."
      refute result =~ "/"
      refute result =~ "\\"
    end

    test "strips backslashes (Windows traversal)" do
      {:ok, result} = Sanitizer.filename("..\\Windows\\System32")
      refute result =~ "\\"
      refute result =~ ".."
    end

    test "collapses multiple consecutive dots" do
      {:ok, result} = Sanitizer.filename("file...txt")
      refute result =~ ".."
    end

    test "returns error for empty result" do
      assert {:error, :empty} = Sanitizer.filename("../../../")
      assert {:error, :empty} = Sanitizer.filename("")
      assert {:error, :empty} = Sanitizer.filename("\0\0\0")
    end

    test "strips characters outside safe set" do
      {:ok, result} = Sanitizer.filename("file;name|bad.txt")
      refute result =~ ";"
      refute result =~ "|"
    end
  end

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  # Used to unwrap an {:ok, val} and call a transform on val
  defp strip_dots_ok({:ok, val}), do: {:ok, String.replace(val, ".", "_")}
  defp strip_dots_ok(other), do: other
end
