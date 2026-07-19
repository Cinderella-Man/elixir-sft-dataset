defmodule GenTask.SpecFim do
  @moduledoc """
  The spec-FIM carve, shared by the miner (`scripts/mint_specfim.exs`) and the
  drift gate (`scripts/resync_specfim_embeds.exs`) — one implementation, so a
  carve-rule change cannot fork the two (the F24 lesson generalized).

  A SITE is one top-level `@spec` attribute of a single-module gold:
  `%{id: "name/arity", lo: line, hi: line, span: verbatim source}`. Invalid
  sites (unparseable span, duplicate name/arity) carry `{:invalid, reason}`
  ids — enumerated, never silently dropped, so miners can ledger them.
  """

  alias GenTask.SpecFimTemplate

  @doc "Every top-level `@spec` attribute site in the module source."
  @spec spec_sites(String.t()) :: [map()]
  def spec_sites(src) do
    lines = String.split(src, "\n")

    sites =
      lines
      |> Enum.with_index()
      |> Enum.filter(fn {l, _} -> String.match?(l, ~r/^\s*@spec\s/) end)
      |> Enum.map(fn {_, i} -> build_site(lines, i) end)

    ids = sites |> Enum.map(& &1.id) |> Enum.frequencies()

    Enum.map(sites, fn site ->
      cond do
        site.id == :unparseable ->
          %{site | id: {:invalid, "spec span does not parse"}}

        Map.fetch!(ids, site.id) > 1 ->
          %{site | id: {:invalid, "duplicate name/arity: #{site.id}"}}

        true ->
          site
      end
    end)
  end

  @doc "The site with the given `\"name/arity\"` id, or nil."
  @spec site_by_id(String.t(), String.t()) :: map() | nil
  def site_by_id(src, id), do: Enum.find(spec_sites(src), &(&1.id == id))

  @doc """
  The module with the site's attribute replaced by the `# TODO: @spec` marker
  at the attribute's indent.
  """
  @spec skeleton(String.t(), map()) :: String.t()
  def skeleton(src, site) do
    lines = String.split(src, "\n")
    indent = Regex.run(~r/^(\s*)/, Enum.at(lines, site.lo)) |> hd()
    marker = indent <> SpecFimTemplate.marker()

    (Enum.slice(lines, 0, site.lo) ++ [marker] ++ Enum.slice(lines, (site.hi + 1)..-1//1))
    |> Enum.join("\n")
  end

  @doc "True iff marker→span substitution reproduces the parent byte-exactly."
  @spec round_trip?(String.t(), map()) :: boolean()
  def round_trip?(src, site) do
    skel_lines = skeleton(src, site) |> String.split("\n")

    reconstructed =
      (Enum.slice(skel_lines, 0, site.lo) ++
         String.split(site.span, "\n") ++ Enum.slice(skel_lines, (site.lo + 1)..-1//1))
      |> Enum.join("\n")

    reconstructed == src
  end

  defp build_site(lines, lo) do
    Enum.reduce_while(lo..min(lo + 15, length(lines) - 1), nil, fn hi, _ ->
      span = lines |> Enum.slice(lo..hi) |> Enum.join("\n")

      case Code.string_to_quoted(String.trim(span)) do
        {:ok, {:@, _, [{:spec, _, [expr]}]}} ->
          # F26: parse success is NOT span-end — a union type's first
          # alternative parses as a complete spec (`@spec f(x) ::\n {:ok, t}`
          # halted before `| {:error, …}`, truncating the gold and orphaning
          # the continuation under the marker; caught by the corpus format
          # gate 2026-07-19). The span ends only when the NEXT line is not a
          # continuation of the attribute.
          if continuation?(Enum.at(lines, hi + 1)) do
            {:cont, %{id: :unparseable, lo: lo, hi: hi, span: span}}
          else
            {:halt, %{id: site_id(expr), lo: lo, hi: hi, span: span}}
          end

        _ ->
          {:cont, %{id: :unparseable, lo: lo, hi: hi, span: span}}
      end
    end)
  end

  defp continuation?(nil), do: false

  defp continuation?(line) do
    t = String.trim(line)
    String.starts_with?(t, ["|", "when ", "::"])
  end

  defp site_id(expr) do
    case head_of(expr) do
      {name, args} when is_atom(name) -> "#{name}/#{length(args)}"
      _ -> :unparseable
    end
  end

  defp head_of({:"::", _, [head, _ret]}), do: head_call(head)
  defp head_of({:when, _, [inner, _]}), do: head_of(inner)
  defp head_of(_), do: :error

  defp head_call({name, _, nil}) when is_atom(name), do: {name, []}
  defp head_call({name, _, args}) when is_atom(name) and is_list(args), do: {name, args}
  defp head_call(_), do: :error
end
