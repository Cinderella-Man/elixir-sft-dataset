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
      assert {:ok, "etcpasswd",
              [:removed_path_separators, :collapsed_dots, :trimmed_dots]} =
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
end