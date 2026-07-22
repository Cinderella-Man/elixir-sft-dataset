defmodule Sanitizer do
  @moduledoc """
  Cleans and validates untrusted user input against common injection and
  traversal attacks.

  Three independent sanitizers are provided:

    * `html/2` — strips HTML down to a small allowlist of tags, dropping every
      attribute except `href` on `<a>` and refusing `javascript:` URLs.
    * `sql_identifier/1` — reduces a string to a token that is safe to
      interpolate as a SQL table or column name.
    * `filename/1` — reduces a string to a safe, traversal-free filename.

  The HTML sanitizer is a hand-rolled scanner (no external parser) and is
  deliberately conservative: anything it does not understand is discarded
  rather than passed through.
  """

  @default_allow ["b", "i", "em", "strong", "a"]

  # Tags whose *content* is not markup and must be dropped wholesale when the
  # tag itself is not allowed.
  @raw_content_tags ["script", "style", "noscript", "iframe"]

  # Void elements never have a closing tag or inner content.
  @void_tags ~w(area base br col embed hr img input link meta param source track wbr)

  @doc """
  Strips HTML tags from `input`, keeping only those in the allowlist.

  ## Options

    * `:allow` — list of lowercase tag names to keep. Defaults to
      `#{inspect(@default_allow)}`.

  ## Rules

    * Every attribute is stripped, except `href` on `<a>` tags.
    * An `href` whose value begins with `javascript:` (case-insensitive,
      leading whitespace and control characters ignored) causes the `<a>` tag
      to be dropped, keeping only its inner text.
    * Tags outside the allowlist are removed but their inner text is kept,
      except for `script`, `style`, `noscript` and `iframe`, whose content is
      dropped along with the tag.
    * Comments, CDATA, doctypes and processing instructions are removed.

  ## Examples

      iex> Sanitizer.html("<b>hi</b><script>alert(1)</script>")
      "<b>hi</b>"

      iex> Sanitizer.html(~s(<a href="javascript:alert(1)">click</a>))
      "click"

      iex> Sanitizer.html("<div onclick='x'>text</div>")
      "text"

      iex> Sanitizer.html("<span>keep</span>", allow: ["span"])
      "<span>keep</span>"
  """
  @spec html(String.t(), keyword()) :: String.t()
  def html(input, opts \\ []) when is_binary(input) and is_list(opts) do
    allow =
      opts
      |> Keyword.get(:allow, @default_allow)
      |> Enum.map(&(&1 |> to_string() |> String.downcase()))
      |> MapSet.new()

    input
    |> scan([], allow)
    |> IO.iodata_to_binary()
  end

  @doc """
  Sanitizes `input` for use as a SQL identifier (table or column name).

  Every character that is not alphanumeric or an underscore is removed. If the
  result would start with a digit an underscore is prepended, so the value is
  always a valid bare identifier.

  Returns `{:ok, identifier}` or `{:error, :empty}` when nothing survives.

  ## Examples

      iex> Sanitizer.sql_identifier("users; DROP TABLE x")
      {:ok, "usersDROPTABLEx"}

      iex> Sanitizer.sql_identifier("2fast")
      {:ok, "_2fast"}

      iex> Sanitizer.sql_identifier("!!!")
      {:error, :empty}
  """
  @spec sql_identifier(String.t()) :: {:ok, String.t()} | {:error, :empty}
  def sql_identifier(input) when is_binary(input) do
    cleaned =
      input
      |> String.replace(~r/[^A-Za-z0-9_]/, "")

    cond do
      cleaned == "" -> {:error, :empty}
      String.match?(cleaned, ~r/^[0-9]/) -> {:ok, "_" <> cleaned}
      true -> {:ok, cleaned}
    end
  end

  @doc """
  Sanitizes `input` into a safe filename with no path or traversal component.

  Null bytes, path separators (`/` and `\\`) and `..` sequences are removed,
  any character outside `[A-Za-z0-9_.-]` is dropped, and runs of dots are
  collapsed to a single dot.

  Returns `{:ok, filename}` or `{:error, :empty}` when nothing survives.

  ## Examples

      iex> Sanitizer.filename("../../etc/passwd")
      {:ok, "etcpasswd"}

      iex> Sanitizer.filename("report<>.pdf")
      {:ok, "report.pdf"}

      iex> Sanitizer.filename("///")
      {:error, :empty}
  """
  @spec filename(String.t()) :: {:ok, String.t()} | {:error, :empty}
  def filename(input) when is_binary(input) do
    cleaned =
      input
      |> String.replace("\0", "")
      |> String.replace(~r{[/\\]}, "")
      |> strip_dot_dot()
      |> String.replace(~r/[^A-Za-z0-9_.\-]/, "")
      |> String.replace(~r/\.{2,}/, ".")

    if cleaned == "", do: {:error, :empty}, else: {:ok, cleaned}
  end

  # Repeatedly removes ".." so that overlapping sequences such as "...." or
  # "..\..." cannot reconstitute a traversal after a single pass.
  @spec strip_dot_dot(String.t()) :: String.t()
  defp strip_dot_dot(string) do
    replaced = String.replace(string, "..", "")
    if replaced == string, do: string, else: strip_dot_dot(replaced)
  end

  # --- HTML scanner ---------------------------------------------------------
  #
  # `scan/3` walks the input one character at a time. Text is emitted with its
  # HTML metacharacters escaped; tags are parsed, filtered against the
  # allowlist and either re-emitted in a normalized form or dropped.

  @spec scan(String.t(), iodata(), MapSet.t()) :: iodata()
  defp scan("", acc, _allow), do: Enum.reverse(acc)

  defp scan("<!--" <> rest, acc, allow) do
    scan(discard_until(rest, "-->"), acc, allow)
  end

  defp scan("<![" <> rest, acc, allow) do
    scan(discard_until(rest, "]]>"), acc, allow)
  end

  defp scan("<!" <> rest, acc, allow) do
    scan(discard_until(rest, ">"), acc, allow)
  end

  defp scan("<?" <> rest, acc, allow) do
    scan(discard_until(rest, ">"), acc, allow)
  end

  defp scan("<" <> rest, acc, allow) do
    case parse_tag(rest) do
      {:ok, tag, remainder} -> handle_tag(tag, remainder, acc, allow)
      :error -> scan(rest, ["&lt;" | acc], allow)
    end
  end

  defp scan(<<char::utf8, rest::binary>>, acc, allow) do
    scan(rest, [escape_char(char) | acc], allow)
  end

  # A stray byte that is not valid UTF-8: drop it rather than crash.
  defp scan(<<_byte, rest::binary>>, acc, allow), do: scan(rest, acc, allow)

  @spec escape_char(integer()) :: binary()
  defp escape_char(?<), do: "&lt;"
  defp escape_char(?>), do: "&gt;"
  defp escape_char(?&), do: "&amp;"
  defp escape_char(char), do: <<char::utf8>>

  @spec handle_tag(map(), String.t(), iodata(), MapSet.t()) :: iodata()
  defp handle_tag(%{name: name, closing?: true}, rest, acc, allow) do
    if MapSet.member?(allow, name) and name not in @void_tags do
      scan(rest, ["</#{name}>" | acc], allow)
    else
      scan(rest, acc, allow)
    end
  end

  defp handle_tag(%{name: name} = tag, rest, acc, allow) do
    cond do
      not MapSet.member?(allow, name) and name in @raw_content_tags ->
        scan(drop_raw_content(rest, name), acc, allow)

      not MapSet.member?(allow, name) ->
        scan(rest, acc, allow)

      true ->
        emit_open_tag(tag, rest, acc, allow)
    end
  end

  @spec emit_open_tag(map(), String.t(), iodata(), MapSet.t()) :: iodata()
  defp emit_open_tag(%{name: "a", attrs: attrs, self_closing?: self_closing?}, rest, acc, allow) do
    case safe_href(attrs) do
      {:ok, href} ->
        open = ~s(<a href="#{escape_attr(href)}">)
        emit_normalized("a", open, self_closing?, rest, acc, allow)

      :none ->
        emit_normalized("a", "<a>", self_closing?, rest, acc, allow)

      :unsafe ->
        # Drop the anchor entirely, keeping the inner text produced by the
        # continued scan of `rest`.
        scan(rest, acc, allow)
    end
  end

  defp emit_open_tag(%{name: name, self_closing?: self_closing?}, rest, acc, allow) do
    emit_normalized(name, "<#{name}>", self_closing?, rest, acc, allow)
  end

  @spec emit_normalized(String.t(), String.t(), boolean(), String.t(), iodata(), MapSet.t()) ::
          iodata()
  defp emit_normalized(name, open, self_closing?, rest, acc, allow) do
    cond do
      name in @void_tags -> scan(rest, ["<#{name} />" | acc], allow)
      self_closing? -> scan(rest, [open <> "</#{name}>" | acc], allow)
      true -> scan(rest, [open | acc], allow)
    end
  end

  # Returns the first usable href, or `:unsafe` when it points at a
  # `javascript:` (or otherwise scripted) URL.
  @spec safe_href(list({String.t(), String.t()})) :: {:ok, String.t()} | :none | :unsafe
  defp safe_href(attrs) do
    case List.keyfind(attrs, "href", 0) do
      nil -> :none
      {_key, value} -> classify_href(value)
    end
  end

  @spec classify_href(String.t()) :: {:ok, String.t()} | :none | :unsafe
  defp classify_href(value) do
    normalized =
      value
      |> String.replace(~r/[\s\x00-\x20]/u, "")
      |> String.downcase()

    cond do
      normalized == "" -> :none
      String.starts_with?(normalized, "javascript:") -> :unsafe
      true -> {:ok, String.trim(value)}
    end
  end

  @spec escape_attr(String.t()) :: String.t()
  defp escape_attr(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("\"", "&quot;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  # Skips everything up to and including the matching close tag of a
  # raw-content element, so `<script>alert(1)</script>` leaves nothing behind.
  @spec drop_raw_content(String.t(), String.t()) :: String.t()
  defp drop_raw_content(rest, name) do
    case Regex.split(~r{</#{name}\s*>}i, rest, parts: 2) do
      [_dropped, remainder] -> remainder
      [_only] -> ""
    end
  end

  @spec discard_until(String.t(), String.t()) :: String.t()
  defp discard_until(string, terminator) do
    case String.split(string, terminator, parts: 2) do
      [_dropped, rest] -> rest
      [_only] -> ""
    end
  end

  # --- Tag parsing ----------------------------------------------------------

  # Parses the body of a tag (everything after the opening `<`). Returns
  # `:error` when the text is not actually a tag, e.g. a bare `<` in prose.
  @spec parse_tag(String.t()) :: {:ok, map(), String.t()} | :error
  defp parse_tag(rest) do
    {closing?, rest} =
      case rest do
        "/" <> tail -> {true, tail}
        _other -> {false, rest}
      end

    case take_name(rest, []) do
      {"", _rest} ->
        :error

      {name, after_name} ->
        {attrs, self_closing?, remainder} = parse_attrs(after_name, [])
        tag = %{name: name, closing?: closing?, self_closing?: self_closing?, attrs: attrs}
        {:ok, tag, remainder}
    end
  end

  @spec take_name(String.t(), [binary()]) :: {String.t(), String.t()}
  defp take_name(<<char, rest::binary>>, acc) when char in ?a..?z or char in ?A..?Z do
    take_name(rest, [<<char>> | acc])
  end

  defp take_name(<<char, rest::binary>>, acc)
       when acc != [] and (char in ?0..?9 or char in [?-, ?_, ?:]) do
    take_name(rest, [<<char>> | acc])
  end

  defp take_name(rest, acc) do
    name = acc |> Enum.reverse() |> IO.iodata_to_binary() |> String.downcase()
    {name, rest}
  end

  @spec parse_attrs(String.t(), list()) :: {list(), boolean(), String.t()}
  defp parse_attrs("", acc), do: {Enum.reverse(acc), false, ""}
  defp parse_attrs(">" <> rest, acc), do: {Enum.reverse(acc), false, rest}
  defp parse_attrs("/>" <> rest, acc), do: {Enum.reverse(acc), true, rest}

  defp parse_attrs(<<char, rest::binary>>, acc) when char in [?\s, ?\t, ?\n, ?\r, ?\f, ?/] do
    parse_attrs(rest, acc)
  end

  defp parse_attrs(rest, acc) do
    {key, after_key} = take_attr_key(rest, [])

    if key == "" do
      # Unparseable byte inside the tag: skip it and continue.
      <<_skipped, tail::binary>> = rest
      parse_attrs(tail, acc)
    else
      {value, remainder} = take_attr_value(skip_ws(after_key))
      parse_attrs(remainder, [{key, value} | acc])
    end
  end

  @spec take_attr_key(String.t(), [binary()]) :: {String.t(), String.t()}
  defp take_attr_key(<<char, _::binary>> = rest, acc)
       when char in [?\s, ?\t, ?\n, ?\r, ?\f, ?=, ?>, ?/] do
    {acc |> Enum.reverse() |> IO.iodata_to_binary() |> String.downcase(), rest}
  end

  defp take_attr_key(<<char::utf8, rest::binary>>, acc) do
    take_attr_key(rest, [<<char::utf8>> | acc])
  end

  defp take_attr_key(rest, acc) do
    {acc |> Enum.reverse() |> IO.iodata_to_binary() |> String.downcase(), rest}
  end

  @spec take_attr_value(String.t()) :: {String.t(), String.t()}
  defp take_attr_value("=" <> rest), do: read_value(skip_ws(rest))
  defp take_attr_value(rest), do: {"", rest}

  @spec read_value(String.t()) :: {String.t(), String.t()}
  defp read_value(<<quote_char, rest::binary>>) when quote_char in [?", ?'] do
    case :binary.split(rest, <<quote_char>>) do
      [value, remainder] -> {value, remainder}
      [value] -> {value, ""}
    end
  end

  defp read_value(rest), do: read_unquoted(rest, [])

  @spec read_unquoted(String.t(), [binary()]) :: {String.t(), String.t()}
  defp read_unquoted(<<char, _::binary>> = rest, acc)
       when char in [?\s, ?\t, ?\n, ?\r, ?\f, ?>] do
    {acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  end

  defp read_unquoted("", acc), do: {acc |> Enum.reverse() |> IO.iodata_to_binary(), ""}

  defp read_unquoted(<<char::utf8, rest::binary>>, acc) do
    read_unquoted(rest, [<<char::utf8>> | acc])
  end

  defp read_unquoted(<<_byte, rest::binary>>, acc), do: read_unquoted(rest, acc)

  @spec skip_ws(String.t()) :: String.t()
  defp skip_ws(<<char, rest::binary>>) when char in [?\s, ?\t, ?\n, ?\r, ?\f], do: skip_ws(rest)
  defp skip_ws(rest), do: rest
end