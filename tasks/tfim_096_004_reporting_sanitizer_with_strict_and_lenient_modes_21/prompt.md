# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Sanitizer do
  @moduledoc """
  Reporting sanitizer with `:lenient` (default) and `:strict` modes.

  Each function returns a violation report describing what it changed:

    * no violations → `{:ok, cleaned, []}` (both modes)
    * `:lenient` with violations → `{:ok, cleaned, violations}`
    * `:strict` with violations → `{:error, violations}`
    * hard failure (empty result) → `{:error, [:empty]}`

  Standard library only — no external dependencies.
  """

  @type result :: {:ok, String.t(), [atom()]} | {:error, [atom()]}

  # ── SQL identifier ─────────────────────────────────────────────────────────

  @doc """
  Sanitizes `input` into a SQL identifier, keeping only `[A-Za-z0-9_]`.

  Reports `:removed_illegal_chars` when characters were stripped and
  `:prefixed_digit_start` when a leading underscore was prepended because the
  value started with a digit. An empty stripped value is `{:error, [:empty]}`.
  """
  @spec sql_identifier(String.t(), keyword()) :: result()
  def sql_identifier(input, opts \\ []) when is_binary(input) do
    mode = Keyword.get(opts, :mode, :lenient)
    stripped = String.replace(input, ~r/[^a-zA-Z0-9_]/, "")

    if stripped == "" do
      {:error, [:empty]}
    else
      removed = if stripped != input, do: [:removed_illegal_chars], else: []

      {cleaned, prefixed} =
        if String.match?(stripped, ~r/\A[0-9]/) do
          {"_" <> stripped, [:prefixed_digit_start]}
        else
          {stripped, []}
        end

      finalize(mode, cleaned, removed ++ prefixed)
    end
  end

  # ── Filename ───────────────────────────────────────────────────────────────

  @doc """
  Sanitizes `input` into a safe filename.

  Strips null bytes and path separators, keeps only `[A-Za-z0-9_.-]`, collapses
  runs of 2+ dots to one, and trims leading/trailing dots. Reports each of these
  transformations in fixed order. An empty final value is `{:error, [:empty]}`.
  """
  @spec filename(String.t(), keyword()) :: result()
  def filename(input, opts \\ []) when is_binary(input) do
    mode = Keyword.get(opts, :mode, :lenient)

    no_null = String.replace(input, "\0", "")
    no_sep = no_null |> String.replace("/", "") |> String.replace("\\", "")
    filtered = String.replace(no_sep, ~r/[^a-zA-Z0-9_\-.]/, "")
    collapsed = String.replace(filtered, ~r/\.{2,}/, ".")
    trimmed = String.trim(collapsed, ".")

    if trimmed == "" do
      {:error, [:empty]}
    else
      violations =
        []
        |> maybe(String.contains?(input, "\0"), :removed_null_bytes)
        |> maybe(
          String.contains?(input, "/") or String.contains?(input, "\\"),
          :removed_path_separators
        )
        |> maybe(filtered != no_sep, :removed_illegal_chars)
        |> maybe(collapsed != filtered, :collapsed_dots)
        |> maybe(trimmed != collapsed, :trimmed_dots)

      finalize(mode, trimmed, violations)
    end
  end

  # ── Free text ──────────────────────────────────────────────────────────────

  @doc """
  Sanitizes free `text`.

  Strips C0 control characters (except `\\t`, `\\n`, `\\r`), trims surrounding
  whitespace, then HTML-escapes `&`, `<`, `>`, `"`, `'`. Reports each of these
  transformations in fixed order. An empty result is valid (no hard failure).
  """
  @spec text(String.t(), keyword()) :: result()
  def text(input, opts \\ []) when is_binary(input) do
    mode = Keyword.get(opts, :mode, :lenient)

    no_ctrl = String.replace(input, ~r/[\x00-\x08\x0B\x0C\x0E-\x1F]/, "")
    trimmed = String.trim(no_ctrl)
    escaped = html_escape(trimmed)

    violations =
      []
      |> maybe(no_ctrl != input, :removed_control_chars)
      |> maybe(trimmed != no_ctrl, :trimmed_whitespace)
      |> maybe(escaped != trimmed, :escaped_html)

    finalize(mode, escaped, violations)
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  @spec finalize(:lenient | :strict, String.t(), [atom()]) :: result()
  defp finalize(_mode, cleaned, []), do: {:ok, cleaned, []}
  defp finalize(:lenient, cleaned, violations), do: {:ok, cleaned, violations}
  defp finalize(:strict, _cleaned, violations), do: {:error, violations}

  @spec maybe([atom()], boolean(), atom()) :: [atom()]
  defp maybe(list, true, v), do: list ++ [v]
  defp maybe(list, false, _v), do: list

  @spec html_escape(String.t()) :: String.t()
  defp html_escape(s) do
    s
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end
```

## Test harness — implement the `# TODO` test

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
    # TODO
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
