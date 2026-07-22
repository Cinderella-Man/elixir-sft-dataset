defmodule Anonymizer do
  @moduledoc """
  Anonymizes fields inside deeply nested record maps, addressing them by string paths.

  A rule set is a map whose keys are string paths and whose values are rule descriptors:

    * `:hash` — replace the value with its SHA-256 hex digest
    * `:mask` — keep the first and last character, replace the middle with `*`
    * `:redact` — replace the value with `"[REDACTED]"`
    * `{:fake, seed}` — replace the value with a deterministic, realistic-looking fake

  ## Path syntax

    * `"user.email"` descends into nested maps and targets `record[:user][:email]`.
    * `"orders[].card"` descends into every element of the `:orders` list and targets
      the `:card` field of each element.
    * `"tags[]"` targets every scalar element of the `:tags` list.

  Path segments match either atom or string keys, whichever the record actually uses.
  Paths that do not resolve (missing keys, or a type mismatch such as descending into a
  non-map) are skipped rather than raising.

  ## Referential integrity

  Every rule is a pure, deterministic function of the original value (plus the seed, for
  `{:fake, seed}`). Two equal source values addressed by paths sharing the same rule
  therefore always produce the same anonymized output, within a record and across the
  whole list.

  `nil` values are left untouched, since there is nothing meaningful to anonymize.
  """

  @type rule :: :hash | :mask | :redact | {:fake, term()}
  @type rules :: %{optional(String.t()) => rule()}
  @type record :: map()

  @typep segment :: {:key, String.t()} | {:list, String.t()}

  @first_names ~w(
    alex jordan taylor morgan casey riley avery quinn harper rowan sasha devon
    logan emery skylar reese finley marlowe blake noor
  )

  @last_names ~w(
    fletcher morrow whitaker langley hollis marsden ashworth calloway prescott
    ridley thornton vance kessler bramble hawthorne quill nolan draper
  )

  @domains ~w(example.com mailinator.test example.org example.net testmail.example)

  @doc """
  Anonymizes every record in `records` according to `rules`.

  `records` is a list of (possibly deeply nested) maps and `rules` maps string paths to
  rule descriptors. Returns a list of the same length, with the addressed values replaced
  in place; everything else is preserved verbatim.

  ## Examples

      iex> records = [%{user: %{email: "ada@example.com"}, tags: ["vip", "beta"]}]
      iex> [out] = Anonymizer.anonymize(records, %{"user.email" => :redact, "tags[]" => :mask})
      iex> out.user.email
      "[REDACTED]"
      iex> out.tags
      ["v*p", "b**a"]

  """
  @spec anonymize([record()], rules()) :: [record()]
  def anonymize(records, rules) when is_list(records) and is_map(rules) do
    compiled =
      Enum.map(rules, fn {path, rule} -> {parse_path(path), rule} end)

    Enum.map(records, fn record ->
      Enum.reduce(compiled, record, fn {segments, rule}, acc ->
        update_path(acc, segments, rule)
      end)
    end)
  end

  ## Path parsing

  @spec parse_path(String.t()) :: [segment()]
  defp parse_path(path) do
    path
    |> String.split(".", trim: true)
    |> Enum.map(&parse_segment/1)
  end

  @spec parse_segment(String.t()) :: segment()
  defp parse_segment(segment) do
    if String.ends_with?(segment, "[]") do
      {:list, String.replace_suffix(segment, "[]", "")}
    else
      {:key, segment}
    end
  end

  ## Traversal

  @spec update_path(term(), [segment()], rule()) :: term()
  defp update_path(value, [], rule), do: transform(value, rule)

  defp update_path(map, [{:key, key} | rest], rule) when is_map(map) do
    case fetch_key(map, key) do
      {:ok, actual_key, value} -> Map.put(map, actual_key, update_path(value, rest, rule))
      :error -> map
    end
  end

  defp update_path(map, [{:list, key} | rest], rule) when is_map(map) do
    case fetch_key(map, key) do
      {:ok, actual_key, list} when is_list(list) ->
        Map.put(map, actual_key, Enum.map(list, &update_path(&1, rest, rule)))

      _other ->
        map
    end
  end

  defp update_path(other, _segments, _rule), do: other

  @doc false
  @spec fetch_key(map(), String.t()) :: {:ok, term(), term()} | :error
  defp fetch_key(map, key) do
    cond do
      Map.has_key?(map, key) ->
        {:ok, key, Map.fetch!(map, key)}

      true ->
        map
        |> Map.keys()
        |> Enum.find(fn k -> is_atom(k) and Atom.to_string(k) == key end)
        |> case do
          nil -> :error
          atom_key -> {:ok, atom_key, Map.fetch!(map, atom_key)}
        end
    end
  end

  ## Rules

  @spec transform(term(), rule()) :: term()
  defp transform(nil, _rule), do: nil
  defp transform(value, :hash), do: hash(canonical(value))
  defp transform(value, :mask), do: mask(canonical(value))
  defp transform(_value, :redact), do: "[REDACTED]"
  defp transform(value, {:fake, seed}), do: fake(canonical(value), canonical(seed))
  defp transform(value, _unknown_rule), do: value

  @spec canonical(term()) :: String.t()
  defp canonical(value) when is_binary(value), do: value
  defp canonical(value) when is_atom(value), do: Atom.to_string(value)
  defp canonical(value) when is_number(value), do: to_string(value)
  defp canonical(value), do: inspect(value)

  @spec hash(String.t()) :: String.t()
  defp hash(value) do
    :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  end

  @spec mask(String.t()) :: String.t()
  defp mask(value) do
    case String.graphemes(value) do
      [] ->
        ""

      [_single] ->
        "*"

      [first | rest] ->
        {middle, [last]} = Enum.split(rest, length(rest) - 1)
        first <> String.duplicate("*", length(middle)) <> last
    end
  end

  ## Deterministic fakes

  @spec fake(String.t(), String.t()) :: String.t()
  defp fake(value, seed) do
    digest = :crypto.hash(:sha256, "fake|" <> seed <> "|" <> value)

    cond do
      String.contains?(value, "@") -> fake_email(digest)
      numeric_shaped?(value) -> fake_numeric(value, digest)
      true -> fake_name(digest)
    end
  end

  @spec numeric_shaped?(String.t()) :: boolean()
  defp numeric_shaped?(value) do
    Regex.match?(~r/^[0-9][0-9()+\-\s\.]*$/u, value) and
      String.length(String.replace(value, ~r/[^0-9]/u, "")) >= 4
  end

  @spec fake_email(binary()) :: String.t()
  defp fake_email(digest) do
    first = pick(@first_names, digest, 0)
    last = pick(@last_names, digest, 1)
    domain = pick(@domains, digest, 2)
    suffix = digest |> :binary.at(3) |> Integer.to_string()

    "#{first}.#{last}#{suffix}@#{domain}"
  end

  @spec fake_name(binary()) :: String.t()
  defp fake_name(digest) do
    first = @first_names |> pick(digest, 0) |> String.capitalize()
    last = @last_names |> pick(digest, 1) |> String.capitalize()

    first <> " " <> last
  end

  @spec fake_numeric(String.t(), binary()) :: String.t()
  defp fake_numeric(value, digest) do
    value
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.map_join(fn {grapheme, index} ->
      if grapheme =~ ~r/^[0-9]$/ do
        digest |> :binary.at(rem(index, byte_size(digest))) |> rem(10) |> Integer.to_string()
      else
        grapheme
      end
    end)
  end

  @spec pick([String.t()], binary(), non_neg_integer()) :: String.t()
  defp pick(choices, digest, offset) do
    byte = :binary.at(digest, rem(offset, byte_size(digest)))
    Enum.at(choices, rem(byte, length(choices)))
  end
end