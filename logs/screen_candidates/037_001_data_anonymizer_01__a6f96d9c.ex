defmodule Anonymizer do
  @moduledoc """
  Anonymizes fields of tabular-ish data: a list of maps ("records") transformed
  according to a rule map.

  Supported rules, keyed by field name (an atom):

    * `:hash` — replace the value with its SHA-256 hex digest.
    * `:mask` — keep the first and last character, replace the middle with `*`.
      Two-character strings are returned unchanged; one-character strings become
      `"*"`.
    * `:redact` — replace the value with `"[REDACTED]"`.
    * `{:fake, seed}` — replace the value with a deterministic, realistic-looking
      but fabricated string derived solely from the original value and `seed`.

  All rules are pure functions of the original value (and, for `{:fake, seed}`,
  the seed), so referential integrity is preserved for free: equal inputs always
  map to equal outputs, both within a record and across the whole list.

  Values that are not binaries are stringified with `inspect/1` before being
  transformed, so any term can be anonymized consistently. Fields absent from a
  record, and fields not mentioned in the rules, are left untouched.

      iex> Anonymizer.anonymize([%{name: "Ada", city: "Bath"}], %{name: :redact})
      [%{name: "[REDACTED]", city: "Bath"}]
  """

  @redaction "[REDACTED]"

  @typedoc "A rule describing how a single field must be anonymized."
  @type rule :: :hash | :mask | :redact | {:fake, term()}

  @typedoc "A mapping of field name to the rule applied to that field."
  @type rules :: %{optional(atom()) => rule()}

  @typedoc "A single input/output record."
  @type record :: map()

  @first_names ~w(
    Alice Brian Carla Diego Elena Farid Grace Hannah Ibrahim Julia Kenji Lena
    Marco Nadia Omar Priya Quentin Rosa Samir Tomas Ulrike Viktor Wendy Xiomara
    Yusuf Zara
  )

  @last_names ~w(
    Abbott Bennett Castillo Duarte Ellery Fontaine Grimaldi Halvorsen Iverson
    Jenkins Kowalski Lindqvist Moreau Nakamura Okonkwo Petrov Quintana Rasmussen
    Sandoval Thorne Ustinov Vasquez Whitfield Xanthos Yamada Zielinski
  )

  @domains ~w(example.com example.net example.org mail.example.com test.example.io)

  @streets ~w(Maple Oak Cedar Birch Willow Juniper Aspen Chestnut Linden Hawthorn)

  @street_types ~w(Street Avenue Road Lane Way Boulevard)

  @cities ~w(
    Ashford Bridgeport Clearwater Dunmore Eastvale Fairhaven Glenrock Hartwell
    Ironwood Kingsley Lakeview Millbrook Northgate Oakhurst
  )

  @doc """
  Anonymizes `records` according to `rules`.

  Returns a list of the same length and shape as `records`, with every field
  named in `rules` replaced by its anonymized counterpart. Fields not mentioned
  in `rules`, and fields missing from a given record, are left as-is.

  Referential integrity holds across the whole list: identical original values
  for a field always yield identical anonymized values.

  ## Examples

      iex> records = [%{email: "a@x.com", id: 1}, %{email: "a@x.com", id: 2}]
      iex> [%{email: e1}, %{email: e2}] = Anonymizer.anonymize(records, %{email: :mask})
      iex> {e1, e2}
      {"a*****m", "a*****m"}

      iex> Anonymizer.anonymize([%{pin: "1234"}], %{pin: :mask})
      [%{pin: "1**4"}]
  """
  @spec anonymize([record()], rules()) :: [record()]
  def anonymize(records, rules) when is_list(records) and is_map(rules) do
    Enum.map(records, &anonymize_record(&1, rules))
  end

  @spec anonymize_record(record(), rules()) :: record()
  defp anonymize_record(record, rules) when is_map(record) do
    Enum.reduce(rules, record, fn {field, rule}, acc ->
      case Map.fetch(acc, field) do
        {:ok, value} -> Map.put(acc, field, apply_rule(rule, value))
        :error -> acc
      end
    end)
  end

  @spec apply_rule(rule(), term()) :: String.t()
  defp apply_rule(:hash, value), do: hash(to_string_value(value))
  defp apply_rule(:mask, value), do: mask(to_string_value(value))
  defp apply_rule(:redact, _value), do: @redaction
  defp apply_rule({:fake, seed}, value), do: fake(to_string_value(value), seed)

  defp apply_rule(rule, _value) do
    raise ArgumentError, "unknown anonymization rule: #{inspect(rule)}"
  end

  @spec to_string_value(term()) :: String.t()
  defp to_string_value(value) when is_binary(value), do: value
  defp to_string_value(value), do: inspect(value)

  @spec hash(String.t()) :: String.t()
  defp hash(value) do
    :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  end

  @spec mask(String.t()) :: String.t()
  defp mask(value) do
    case String.graphemes(value) do
      [] -> ""
      [_single] -> "*"
      [first, last] -> first <> last
      [first | rest] -> mask_middle(first, rest)
    end
  end

  @spec mask_middle(String.t(), [String.t()]) :: String.t()
  defp mask_middle(first, rest) do
    {middle, [last]} = Enum.split(rest, length(rest) - 1)
    first <> String.duplicate("*", length(middle)) <> last
  end

  # Deterministic fake generation.
  #
  # A single SHA-256 digest over `seed <> "\\0" <> value` is the only entropy
  # source; distinct byte ranges of that digest select each component of the
  # fabricated value. Same value + same seed => same digest => same output.
  @spec fake(String.t(), term()) :: String.t()
  defp fake(value, seed) do
    digest = :crypto.hash(:sha256, [seed_to_binary(seed), <<0>>, value])
    shape = detect_shape(value)
    build_fake(shape, digest)
  end

  @spec seed_to_binary(term()) :: binary()
  defp seed_to_binary(seed) when is_binary(seed), do: seed
  defp seed_to_binary(seed), do: :erlang.term_to_binary(seed)

  @spec detect_shape(String.t()) :: :email | :phone | :address | :name
  defp detect_shape(value) do
    cond do
      String.contains?(value, "@") -> :email
      phone_like?(value) -> :phone
      address_like?(value) -> :address
      true -> :name
    end
  end

  @spec phone_like?(String.t()) :: boolean()
  defp phone_like?(value) do
    digits = String.replace(value, ~r/[^0-9]/, "")
    String.length(digits) >= 7 and String.match?(value, ~r/^[\d\s\-\+\(\)\.]+$/)
  end

  @spec address_like?(String.t()) :: boolean()
  defp address_like?(value), do: String.match?(value, ~r/^\d+\s+\S/)

  @spec build_fake(:email | :phone | :address | :name, binary()) :: String.t()
  defp build_fake(:name, digest) do
    "#{pick(@first_names, digest, 0)} #{pick(@last_names, digest, 1)}"
  end

  defp build_fake(:email, digest) do
    first = pick(@first_names, digest, 0)
    last = pick(@last_names, digest, 1)
    domain = pick(@domains, digest, 2)
    suffix = rem(byte_at(digest, 3), 100)

    "#{String.downcase(first)}.#{String.downcase(last)}#{suffix}@#{domain}"
  end

  defp build_fake(:phone, digest) do
    area = 200 + rem(number_at(digest, 0, 2), 800)
    exchange = 200 + rem(number_at(digest, 2, 2), 800)
    line = rem(number_at(digest, 4, 2), 10_000)

    "+1-#{area}-#{exchange}-#{pad(line, 4)}"
  end

  defp build_fake(:address, digest) do
    number = 1 + rem(number_at(digest, 0, 2), 9999)
    street = pick(@streets, digest, 2)
    type = pick(@street_types, digest, 3)
    city = pick(@cities, digest, 4)

    "#{number} #{street} #{type}, #{city}"
  end

  @spec pick([String.t()], binary(), non_neg_integer()) :: String.t()
  defp pick(list, digest, index) do
    Enum.at(list, rem(number_at(digest, index * 2, 2), length(list)))
  end

  @spec byte_at(binary(), non_neg_integer()) :: non_neg_integer()
  defp byte_at(digest, index) do
    :binary.at(digest, rem(index, byte_size(digest)))
  end

  @spec number_at(binary(), non_neg_integer(), pos_integer()) :: non_neg_integer()
  defp number_at(digest, offset, size) do
    offset..(offset + size - 1)
    |> Enum.reduce(0, fn index, acc -> acc * 256 + byte_at(digest, index) end)
  end

  @spec pad(non_neg_integer(), pos_integer()) :: String.t()
  defp pad(number, width) do
    number |> Integer.to_string() |> String.pad_leading(width, "0")
  end
end