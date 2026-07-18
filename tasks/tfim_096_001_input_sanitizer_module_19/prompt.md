# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Sanitizer do
  @moduledoc """
  Cleans and validates user inputs against common injection and traversal attacks.

  All functions are pure (no side-effects, no external dependencies) and rely
  solely on the Elixir / Erlang standard library.
  """

  # ---------------------------------------------------------------------------
  # HTML sanitization
  # ---------------------------------------------------------------------------

  @default_allow ~w[b i em strong a]

  # Tags whose *content* (inner text/markup) must be discarded entirely, not
  # just the tag itself.  These are raw/executable contexts — stripping just
  # the tag wrapper would still leave runnable code in the output.
  @raw_content_tags ~w[script style noscript iframe]

  @doc """
  Strips HTML tags that are not present in the allowlist.

  ## Options

    * `:allow` – list of lowercase tag names to permit
      (default: #{inspect(@default_allow)}).

  ## Rules

    * Raw-content tags (`script`, `style`, `noscript`, `iframe`) are removed
      **together with their inner content**.
    * Tags not in the allowlist are stripped but their inner text is preserved.
    * All attributes are stripped from every allowed tag **except** `href` on
      `<a>` tags.
    * Any `href` whose value starts with `javascript:` (case-insensitive,
      ignoring leading ASCII whitespace/control chars) is unsafe — the `<a>`
      tag is dropped and only its inner text is kept.

  ## Examples

      iex> Sanitizer.html("<b>Hello</b> <script>alert(1)</script>world")
      "<b>Hello</b> world"

      iex> Sanitizer.html("<a href=\\"https://example.com\\">link</a>")
      "<a href=\\"https://example.com\\">link</a>"

      iex> Sanitizer.html("<a href=\\"javascript:alert(1)\\">click</a>")
      "click"

      iex> Sanitizer.html("<span class=\\"x\\"><b>bold</b></span>")
      "<b>bold</b>"

      iex> Sanitizer.html("<b class=\\"danger\\">text</b>")
      "<b>text</b>"

      iex> Sanitizer.html("<B>Hello</B>")
      "<b>Hello</b>"

  """
  @spec html(String.t(), keyword()) :: String.t()
  def html(input, opts \\ []) when is_binary(input) do
    allow = opts |> Keyword.get(:allow, @default_allow) |> Enum.map(&String.downcase/1)

    input
    |> strip_raw_content_tags()
    |> parse_html(allow)
  end

  # ── Phase 1: nuke raw-content tags and everything inside them ──────────────

  # Uses a case-insensitive, dotall regex so multiline script blocks are caught.
  @raw_tag_pattern Enum.join(@raw_content_tags, "|")
  @raw_tag_re Regex.compile!(
                "<(#{@raw_tag_pattern})(\\s[^>]*)?>.*?<\\/\\1>",
                [:caseless, :dotall]
              )

  defp strip_raw_content_tags(input),
    do: Regex.replace(@raw_tag_re, input, "")

  # ── Phase 2: hand-rolled single-pass tag parser ────────────────────────────
  #
  # Parser states
  #   :text – reading regular character data
  #   :tag  – reading inside a < … > sequence
  #
  # Extra state `poisoned_a` (boolean):
  #   Becomes `true` when we emit *nothing* for an opening <a> because its
  #   href was a javascript: URI.  While true we also suppress the matching
  #   </a>.  Resets to `false` once the closing tag is consumed.
  #
  # `acc`  – iodata accumulator for the final output
  # `buf`  – string buffer for the token currently being built

  defp parse_html(input, allow) do
    {result, _} = do_parse(input, allow, [], :text, "", _poisoned_a = false)
    IO.iodata_to_binary(result)
  end

  defp do_parse("", _allow, acc, :text, buf, _pa),
    do: {[acc, buf], false}

  defp do_parse("", _allow, acc, :tag, buf, _pa),
    # Unclosed tag at EOF — treat as literal text
    do: {[acc, "<", buf], false}

  defp do_parse("<" <> rest, allow, acc, :text, buf, pa),
    do: do_parse(rest, allow, [acc, buf], :tag, "", pa)

  defp do_parse(">" <> rest, allow, acc, :tag, buf, pa) do
    {tag_out, new_pa} = process_tag(buf, allow, pa)
    do_parse(rest, allow, [acc, tag_out], :text, "", new_pa)
  end

  defp do_parse(<<ch::utf8, rest::binary>>, allow, acc, state, buf, pa),
    do: do_parse(rest, allow, acc, state, buf <> <<ch::utf8>>, pa)

  # ── Tag processor ──────────────────────────────────────────────────────────
  #
  # Returns `{iodata_to_emit, new_poisoned_a}`.

  defp process_tag(raw, allow, pa) do
    trimmed = String.trim(raw)

    cond do
      # HTML comment, doctype, or processing instruction — discard
      String.starts_with?(trimmed, "!") or String.starts_with?(trimmed, "?") ->
        {"", pa}

      # Closing tag
      String.starts_with?(trimmed, "/") ->
        tag_name =
          trimmed
          |> String.slice(1..-1//1)
          |> extract_tag_name()

        cond do
          tag_name == "a" and pa ->
            # Consume the closing </a> of a poisoned anchor; reset state
            {"", false}

          tag_name in allow ->
            {"</#{tag_name}>", pa}

          true ->
            {"", pa}
        end

      # Opening (or self-closing) tag
      true ->
        tag_name = extract_tag_name(trimmed)
        attrs_raw = String.slice(trimmed, String.length(tag_name)..-1//1)
        self_closing? = attrs_raw |> String.trim_trailing() |> String.ends_with?("/")

        if tag_name in allow do
          rebuild_tag(tag_name, attrs_raw, self_closing?, pa)
        else
          {"", pa}
        end
    end
  end

  # ── Attribute helpers ──────────────────────────────────────────────────────

  # Pull the leading tag name from a raw tag string.  Always lowercased.
  defp extract_tag_name(raw) do
    case Regex.run(~r/\A\s*([a-zA-Z][a-zA-Z0-9\-]*)/, raw, capture: :all_but_first) do
      [name] -> String.downcase(name)
      _ -> ""
    end
  end

  # Rebuild an allowed tag, retaining only the permitted attributes.
  # Returns `{iodata, new_poisoned_a}`.

  defp rebuild_tag("a", attrs_raw, self_closing?, pa) do
    href = extract_href(attrs_raw)

    case href do
      nil ->
        # No href — emit a clean anchor tag
        {if(self_closing?, do: "<a/>", else: "<a>"), pa}

      href_val ->
        if javascript_href?(href_val) do
          # Poisoned: suppress opening tag, set poisoned state so the
          # closing tag is also suppressed when encountered.
          {"", true}
        else
          escaped = html_escape_attr(href_val)
          tag = if self_closing?, do: ~s(<a href="#{escaped}"/>), else: ~s(<a href="#{escaped}">)
          {tag, pa}
        end
    end
  end

  defp rebuild_tag(name, _attrs_raw, self_closing?, pa) do
    tag = if self_closing?, do: "<#{name}/>", else: "<#{name}>"
    {tag, pa}
  end

  # Extract the value of the `href` attribute from a raw attribute string.
  # Handles double-quoted, single-quoted, and unquoted values.
  defp extract_href(attrs_raw) do
    cond do
      m = Regex.run(~r/\bhref\s*=\s*"([^"]*)"/i, attrs_raw, capture: :all_but_first) ->
        hd(m)

      m = Regex.run(~r/\bhref\s*=\s*'([^']*)'/i, attrs_raw, capture: :all_but_first) ->
        hd(m)

      m = Regex.run(~r/\bhref\s*=\s*([^\s>\/]+)/i, attrs_raw, capture: :all_but_first) ->
        hd(m)

      true ->
        nil
    end
  end

  # Returns true when an href value is a javascript: URI.
  # Per the HTML spec, leading ASCII whitespace/control chars are stripped
  # before the scheme comparison.
  defp javascript_href?(value) do
    value
    |> String.replace(~r/[\x00-\x20]/, "")
    |> String.downcase()
    |> String.starts_with?("javascript:")
  end

  defp html_escape_attr(s) do
    s
    |> String.replace("&", "&amp;")
    |> String.replace("\"", "&quot;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  # ---------------------------------------------------------------------------
  # SQL identifier sanitization
  # ---------------------------------------------------------------------------

  @doc """
  Ensures `input` is safe for interpolation as a SQL identifier
  (table or column name).

  ## Rules

    * Keeps only alphanumeric characters and underscores.
    * Returns `{:error, :empty}` when the result is the empty string.
    * Prepends `"_"` when the first character is a digit (most SQL dialects
      forbid identifiers that start with a digit).
    * Returns `{:ok, sanitized}` on success.

  ## Examples

      iex> Sanitizer.sql_identifier("users")
      {:ok, "users"}

      iex> Sanitizer.sql_identifier("my-table!")
      {:ok, "mytable"}

      iex> Sanitizer.sql_identifier("123col")
      {:ok, "_123col"}

      iex> Sanitizer.sql_identifier("!@#")
      {:error, :empty}

  """
  @spec sql_identifier(String.t()) :: {:ok, String.t()} | {:error, :empty}
  def sql_identifier(input) when is_binary(input) do
    sanitized = String.replace(input, ~r/[^a-zA-Z0-9_]/, "")

    cond do
      sanitized == "" ->
        {:error, :empty}

      String.match?(sanitized, ~r/\A[0-9]/) ->
        {:ok, "_" <> sanitized}

      true ->
        {:ok, sanitized}
    end
  end

  # ---------------------------------------------------------------------------
  # Filename sanitization
  # ---------------------------------------------------------------------------

  @doc """
  Produces a filesystem-safe filename from `input`.

  ## Rules

    * Strips null bytes (`\\0`).
    * Strips path separators: `/` and `\\`.
    * Keeps only alphanumerics, underscores, hyphens, and dots.
    * Collapses runs of two or more consecutive dots into a single dot —
      this normalises leftover traversal dot-sequences (e.g. `....` after
      slashes are removed) as well as user typos like `hello..world`.
    * Strips any leading or trailing dots that remain after collapsing.
    * Returns `{:error, :empty}` when the result is the empty string.
    * Returns `{:ok, sanitized}` on success.

  ## Examples

      iex> Sanitizer.filename("report.pdf")
      {:ok, "report.pdf"}

      iex> Sanitizer.filename("../../etc/passwd")
      {:ok, "etcpasswd"}

      iex> Sanitizer.filename("hello\\\\world/test..txt")
      {:ok, "helloworldtest.txt"}

      iex> Sanitizer.filename("my file (draft).docx")
      {:ok, "myfiledraft.docx"}

      iex> Sanitizer.filename("/\\\\")
      {:error, :empty}

  """
  @spec filename(String.t()) :: {:ok, String.t()} | {:error, :empty}
  def filename(input) when is_binary(input) do
    sanitized =
      input
      # 1. Strip null bytes.
      |> String.replace("\0", "")
      # 2. Strip path separators (both flavours).  "../../etc/passwd" becomes
      #    "....etcpasswd" — the dot runs are neutralised in steps 4–5.
      |> String.replace("/", "")
      |> String.replace("\\", "")
      # 3. Keep only the safe character set.
      |> String.replace(~r/[^a-zA-Z0-9_\-.]/, "")
      # 4. Collapse runs of two or more consecutive dots to a single dot.
      #    Handles both traversal remnants ("....etcpasswd" → ".etcpasswd")
      #    and double-dot typos ("hello..world" → "hello.world").
      |> String.replace(~r/\.{2,}/, ".")
      # 5. Strip leading/trailing dots left over after collapsing
      #    (e.g. ".etcpasswd" → "etcpasswd").
      |> String.trim(".")

    if sanitized == "" do
      {:error, :empty}
    else
      {:ok, sanitized}
    end
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
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
      # TODO
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
```
