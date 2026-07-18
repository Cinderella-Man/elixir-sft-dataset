# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule Anonymizer do
  @first_names ~w(
    Alice Bob Carol Dave Eve Frank Grace Henry Iris Jack
    Karen Leo Maya Noah Olivia Paul Quinn Rose Sam Tara
    Uma Victor Wendy Xander Yara Zoe Adrian Blair Casey
    Dana Elliot Faye Glenn Harper Indira Jules
  )

  @last_names ~w(
    Smith Jones Williams Brown Taylor Davies Evans Wilson
    Thomas Roberts Johnson Lee Walker Hall Allen Young
    Hernandez King Wright Scott Baker Green Adams Nelson
    Carter Mitchell Perez Turner Campbell Parker Edwards
  )

  @domains ~w(
    example.com mail.net webhost.org fakemail.io testdomain.com
    inbox.dev sample.org placeholder.net demo.io fictitious.com
  )

  def anonymize(records, rules) when is_list(records) and is_map(rules) do
    compiled = Enum.map(rules, fn {path, rule} -> {parse_path(path), rule} end)

    Enum.map(records, fn record ->
      Enum.reduce(compiled, record, fn {segments, rule}, acc ->
        update_path(acc, segments, rule)
      end)
    end)
  end

  # --- Path parsing -----------------------------------------------------------

  defp parse_path(path) do
    path
    |> String.split(".")
    |> Enum.flat_map(&parse_segment/1)
  end

  defp parse_segment(seg) do
    if String.ends_with?(seg, "[]") do
      [{:key, String.trim_trailing(seg, "[]")}, :each]
    else
      [{:key, seg}]
    end
  end

  # --- Path traversal ---------------------------------------------------------

  defp update_path(value, [], rule), do: apply_rule(value, rule)

  defp update_path(map, [{:key, key} | rest], rule) when is_map(map) do
    case fetch_key(map, key) do
      {:ok, actual_key, value} ->
        Map.put(map, actual_key, update_path(value, rest, rule))

      :error ->
        map
    end
  end

  defp update_path(list, [:each | rest], rule) when is_list(list) do
    Enum.map(list, &update_path(&1, rest, rule))
  end

  defp update_path(other, _segments, _rule), do: other

  defp fetch_key(map, key) do
    atom_key = safe_existing_atom(key)

    cond do
      Map.has_key?(map, key) ->
        {:ok, key, Map.fetch!(map, key)}

      atom_key != nil and Map.has_key?(map, atom_key) ->
        {:ok, atom_key, Map.fetch!(map, atom_key)}

      true ->
        :error
    end
  end

  defp safe_existing_atom(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> nil
  end

  # --- Rule dispatch ----------------------------------------------------------

  defp apply_rule(_value, :redact), do: "[REDACTED]"

  defp apply_rule(value, :hash) do
    :crypto.hash(:sha256, to_string(value)) |> Base.encode16(case: :lower)
  end

  defp apply_rule(value, :mask) do
    str = to_string(value)

    case String.length(str) do
      0 -> str
      1 -> "*"
      2 -> str
      len -> String.at(str, 0) <> String.duplicate("*", len - 2) <> String.at(str, len - 1)
    end
  end

  defp apply_rule(value, {:fake, seed}), do: generate_fake(to_string(value), seed)

  # --- Deterministic fake generator -------------------------------------------

  defp generate_fake(value, seed) do
    <<b0, b1, b2, b3, b4, b5, b6, _rest::binary>> =
      :crypto.hash(:sha256, "#{inspect(seed)}:#{value}")

    first = Enum.at(@first_names, rem(b0, length(@first_names)))
    last = Enum.at(@last_names, rem(b1, length(@last_names)))

    case rem(b2, 4) do
      0 ->
        "#{first} #{last}"

      1 ->
        domain = Enum.at(@domains, rem(b3, length(@domains)))
        "#{String.downcase(first)}.#{String.downcase(last)}@#{domain}"

      2 ->
        suffix = rem(b3 * 256 + b4, 9000) + 1000
        "#{first}#{suffix}"

      3 ->
        suffix = rem(b5 * 256 + b6, 90) + 10
        "#{String.downcase(first)}-#{String.downcase(last)}-#{suffix}"
    end
  end
end
```
