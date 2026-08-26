# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.ErrorFormatter do
  @moduledoc """
  Formats an error map for client consumption.

  Error maps are templates: `message`, `short_message` and the strings under
  `details` carry `%{name}` placeholders, while `vars` (and `details`) carry the
  values. Interpolation is deliberately left to the client so messages can be
  localized or reworded.

  That makes key formatting and placeholder rewriting inseparable. Formatting
  only the dictionary keys would break interpolation — a `%{action_name}`
  placeholder cannot be resolved against a `vars` entry that arrived as
  `actionName` — so this module renames both together.

  Values inside `vars` are data, not templates, and are left alone.
  """

  alias AshTypescript.FieldFormatter

  # The maps whose keys a placeholder can refer to.
  @dictionaries [:vars, "vars", :details, "details"]

  @placeholder ~r/%\{([^}]+)\}/

  @doc """
  Formats every key in `error` with `formatter`, rewriting `%{name}`
  placeholders to match the renamed dictionary keys.

  ## Examples

      iex> AshTypescript.ErrorFormatter.format(
      ...>   %{message: "RPC action %{action_name} not found", vars: %{action_name: "foo"}},
      ...>   :camel_case
      ...> )
      %{"message" => "RPC action %{actionName} not found", "vars" => %{"actionName" => "foo"}}

      iex> AshTypescript.ErrorFormatter.format(%{message: "is required"}, :camel_case)
      %{"message" => "is required"}
  """
  def format(error, formatter) when is_map(error) and not is_struct(error) do
    error
    |> rewrite_error(placeholder_renames(error, formatter))
    |> FieldFormatter.format_output_field_names(formatter)
  end

  def format(error, _formatter), do: error

  defp placeholder_renames(error, formatter) do
    @dictionaries
    |> Enum.flat_map(fn key ->
      case Map.get(error, key) do
        dictionary when is_map(dictionary) and not is_struct(dictionary) -> Map.keys(dictionary)
        _ -> []
      end
    end)
    |> Enum.flat_map(fn key ->
      original = to_string(key)
      formatted = FieldFormatter.format_field_name(original, formatter)

      if formatted == original, do: [], else: [{original, formatted}]
    end)
    |> Map.new()
  end

  defp rewrite_error(error, renames) when map_size(renames) == 0, do: error

  defp rewrite_error(error, renames) do
    Map.new(error, fn
      {key, value} when key in [:vars, "vars"] -> {key, value}
      {key, value} -> {key, rewrite_placeholders(value, renames)}
    end)
  end

  # A single pass, so a rewritten name can never be rewritten again.
  defp rewrite_placeholders(value, renames) when is_binary(value) do
    Regex.replace(@placeholder, value, fn full, name ->
      case Map.fetch(renames, name) do
        {:ok, formatted} -> "%{#{formatted}}"
        :error -> full
      end
    end)
  end

  defp rewrite_placeholders(value, renames) when is_map(value) and not is_struct(value) do
    Map.new(value, fn {key, nested} -> {key, rewrite_placeholders(nested, renames)} end)
  end

  defp rewrite_placeholders(value, renames) when is_list(value) do
    Enum.map(value, &rewrite_placeholders(&1, renames))
  end

  defp rewrite_placeholders(value, _renames), do: value
end
