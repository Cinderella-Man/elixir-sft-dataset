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