# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.FieldFormatter do
  @moduledoc """
  Handles field name formatting for input parameters, output fields, and TypeScript generation.

  Delegates to `AshIntrospection.FieldFormatter` for the core functionality.
  """

  alias AshTypescript.TypeSystem.Introspection

  # Delegate core functions to AshIntrospection.FieldFormatter
  defdelegate parse_input_field(field_name, formatter), to: AshIntrospection.FieldFormatter
  defdelegate format_fields(fields, formatter), to: AshIntrospection.FieldFormatter
  defdelegate parse_input_fields(fields, formatter), to: AshIntrospection.FieldFormatter
  defdelegate parse_input_value(value, formatter), to: AshIntrospection.FieldFormatter
  defdelegate format_field_name(field_name, formatter), to: AshIntrospection.FieldFormatter

  @doc """
  Formats a field name for client output, optionally applying resource/type-level
  field_names mapping.

  Use this when formatting field names for client consumption where the field
  might have a custom TypeScript name via the `field_names` DSL option or the
  `typescript_field_names` callback function.

  ## Examples

      iex> AshTypescript.FieldFormatter.format_field_for_client(:user_name, nil, :camel_case)
      "userName"

      iex> AshTypescript.FieldFormatter.format_field_for_client("already_string", nil, :camel_case)
      "alreadyString"

  When a resource or type module is provided with `field_names`/`typescript_field_names` mappings
  (e.g., `:is_active?` → `"isActive"`), the mapped string value is used directly WITHOUT
  additional formatting.
  """
  def format_field_for_client(field, resource_or_type_module \\ nil, formatter)

  def format_field_for_client(field, resource_or_type_module, formatter) when is_atom(field) do
    cond do
      # Check typescript_field_names/0 callback FIRST (for any type module with fields)
      # This includes TypedStructs, NewTypes wrapping maps, and custom Ash types.
      # Takes priority over Ash resource field_names DSL when both are present.
      resource_or_type_module &&
          Introspection.has_typescript_field_names?(resource_or_type_module) ->
        ts_field_names = Introspection.get_typescript_field_names_map(resource_or_type_module)

        case Map.get(ts_field_names, field) do
          mapped when is_binary(mapped) -> mapped
          nil -> format_field_name(field, formatter)
        end

      # Check Ash resource field_names DSL mapping
      resource_or_type_module && is_ash_resource_with_extension?(resource_or_type_module) ->
        case AshTypescript.Resource.Info.get_mapped_field_name(resource_or_type_module, field) do
          # Mapped fields return the exact string to use - no additional formatting
          mapped when is_binary(mapped) -> mapped
          # No mapping found - apply formatter to original field name
          nil -> format_field_name(field, formatter)
        end

      true ->
        format_field_name(field, formatter)
    end
  end

  def format_field_for_client(field, _resource, formatter) when is_binary(field) do
    format_field_name(field, formatter)
  end

  def format_field_for_client(other, _resource, _formatter), do: other

  # Check if module is an Ash resource with AshTypescript.Resource extension
  defp is_ash_resource_with_extension?(module) do
    Code.ensure_loaded?(module) &&
      Ash.Resource.Info.resource?(module) &&
      Spark.extensions(module) |> Enum.member?(AshTypescript.Resource)
  rescue
    _ -> false
  end

  @doc """
  Converts a field name to an atom, applying the formatter for case conversion.

  Unlike `parse_input_field/2` which tries to use existing atoms, this function
  always creates an atom (using String.to_atom/1 for strings that aren't existing atoms).
  Use this when you need guaranteed atom output for field selection.

  ## Examples

      iex> AshTypescript.FieldFormatter.convert_to_field_atom("userName", :camel_case)
      :user_name

      iex> AshTypescript.FieldFormatter.convert_to_field_atom(:user_name, :camel_case)
      :user_name
  """
  def convert_to_field_atom(field_name, _formatter) when is_atom(field_name), do: field_name

  def convert_to_field_atom(field_name, formatter) when is_binary(field_name) do
    result = parse_input_field(field_name, formatter)

    case result do
      atom when is_atom(atom) -> atom
      string when is_binary(string) -> String.to_atom(string)
    end
  end
end
