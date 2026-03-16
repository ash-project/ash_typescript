# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.InputFormatter do
  @moduledoc """
  Formats input data from client format to internal format.

  Converts client-provided field names and values to the internal representation
  expected by Ash actions. Delegates to ValueFormatter for recursive type-aware
  formatting of nested values using `%AshApiSpec.Type{}` structs.
  """

  alias AshTypescript.{FieldFormatter, Rpc.ValueFormatter}
  alias AshTypescript.Resource.Info, as: ResourceInfo

  @doc """
  Formats input data from client format to internal format.
  """
  def format(
        data,
        resource,
        action_name_or_action,
        formatter,
        resource_lookups \\ nil,
        _type_index \\ %{}
      ) do
    {:ok, format_data(data, resource, action_name_or_action, formatter, resource_lookups)}
  catch
    :throw, error ->
      {:error, error}
  end

  # Helper to get action from name or struct
  defp get_action(resource, action_name_or_action) when is_atom(action_name_or_action) do
    Ash.Resource.Info.action(resource, action_name_or_action)
  end

  defp get_action(_resource, %{} = action), do: action

  defp format_data(data, resource, action_name_or_action, formatter, resource_lookups) do
    case data do
      map when is_map(map) and not is_struct(map) ->
        format_map(map, resource, action_name_or_action, formatter, resource_lookups)

      list when is_list(list) ->
        Enum.map(list, fn item ->
          format_data(item, resource, action_name_or_action, formatter, resource_lookups)
        end)

      other ->
        other
    end
  end

  defp format_map(map, resource, action_name_or_action, formatter, resource_lookups) do
    action = get_action(resource, action_name_or_action)

    # Build the expected keys map once for this action
    expected_keys = build_expected_keys_map(resource, action, formatter, resource_lookups)

    Enum.into(map, %{}, fn {key, value} ->
      case Map.get(expected_keys, key) do
        nil ->
          {key, value}

        internal_key ->
          field_type =
            get_input_field_type(action, resource, internal_key, resource_lookups)

          formatted_value = format_value(value, field_type, formatter, resource_lookups)
          {internal_key, formatted_value}
      end
    end)
  end

  @doc """
  Builds a map of expected client field names to internal Elixir field names.
  """
  def build_expected_keys_map(resource, action, _input_formatter, resource_lookups \\ nil) do
    output_formatter = AshTypescript.Rpc.output_field_formatter()
    argument_keys = build_argument_keys(resource, action, output_formatter)
    attribute_keys = build_attribute_keys(resource, action, output_formatter, resource_lookups)
    Map.merge(attribute_keys, argument_keys)
  end

  defp build_argument_keys(resource, action, output_formatter) do
    action.arguments
    |> Enum.filter(&Map.get(&1, :public?, true))
    |> Enum.into(%{}, fn arg ->
      mapped = ResourceInfo.get_mapped_argument_name(resource, action.name, arg.name)

      client_name =
        cond do
          is_binary(mapped) -> mapped
          mapped == arg.name -> FieldFormatter.format_field_name(arg.name, output_formatter)
          true -> FieldFormatter.format_field_name(mapped, output_formatter)
        end

      {client_name, arg.name}
    end)
  end

  defp build_attribute_keys(resource, action, output_formatter, resource_lookups) do
    accept_list = Map.get(action, :accept) || []
    resource_spec = resource_lookups && Map.get(resource_lookups || %{}, resource)

    accept_list
    |> Enum.filter(fn attr_name ->
      case resource_spec do
        %AshApiSpec.Resource{fields: fields} -> Map.has_key?(fields, attr_name)
        _ -> Ash.Resource.Info.attribute(resource, attr_name) != nil
      end
    end)
    |> Enum.into(%{}, fn attr_name ->
      client_name =
        case ResourceInfo.get_mapped_field_name(resource, attr_name) do
          mapped when is_binary(mapped) -> mapped
          nil -> FieldFormatter.format_field_name(attr_name, output_formatter)
        end

      {client_name, attr_name}
    end)
  end

  # Resolve the field type to %AshApiSpec.Type{} and handle struct resources specially
  defp format_value(value, %AshApiSpec.Type{kind: kind} = type_info, formatter, resource_lookups)
       when kind in [:struct, :map] do
    inst = type_info.instance_of || type_info.module

    if inst && is_ash_resource?(inst) && is_map(value) && not is_struct(value) do
      formatted_data =
        ValueFormatter.format(value, type_info, [], formatter, :input, resource_lookups)

      cast_map_to_struct(formatted_data, inst)
    else
      ValueFormatter.format(value, type_info, [], formatter, :input, resource_lookups)
    end
  end

  defp format_value(value, %AshApiSpec.Type{kind: :resource} = type_info, formatter, resource_lookups) do
    inst = type_info.resource_module || type_info.module

    if inst && is_map(value) && not is_struct(value) do
      formatted_data =
        ValueFormatter.format(value, type_info, [], formatter, :input, resource_lookups)

      cast_map_to_struct(formatted_data, inst)
    else
      ValueFormatter.format(value, type_info, [], formatter, :input, resource_lookups)
    end
  end

  # Embedded resources: only format field names, don't cast to struct.
  # Ash handles embedded resource input casting internally.
  defp format_value(value, %AshApiSpec.Type{kind: :embedded_resource} = type_info, formatter, resource_lookups) do
    ValueFormatter.format(value, type_info, [], formatter, :input, resource_lookups)
  end

  defp format_value(value, %AshApiSpec.Type{kind: :array} = type_info, formatter, resource_lookups) do
    item_type = type_info.item_type

    cond do
      # Non-embedded struct/resource items need struct casting
      item_type && match?(%AshApiSpec.Type{kind: k} when k in [:struct, :resource], item_type) ->
        inst = item_type.instance_of || item_type.resource_module || item_type.module

        if inst && is_ash_resource?(inst) && is_list(value) do
          Enum.map(value, fn item ->
            if is_map(item) && not is_struct(item) do
              formatted_item =
                ValueFormatter.format(item, item_type, [], formatter, :input, resource_lookups)

              cast_map_to_struct(formatted_item, inst)
            else
              item
            end
          end)
        else
          ValueFormatter.format(value, type_info, [], formatter, :input, resource_lookups)
        end

      # Embedded resources and everything else: just format, Ash handles casting
      true ->
        ValueFormatter.format(value, type_info, [], formatter, :input, resource_lookups)
    end
  end

  defp format_value(value, %AshApiSpec.Type{} = type_info, formatter, resource_lookups) do
    ValueFormatter.format(value, type_info, [], formatter, :input, resource_lookups)
  end

  # Fallback for nil type
  defp format_value(value, nil, _formatter, _resource_lookups), do: value

  defp is_ash_resource?(module) when is_atom(module) and not is_nil(module) do
    Code.ensure_loaded?(module) == true and
      Ash.Resource.Info.resource?(module)
  end

  defp is_ash_resource?(_), do: false

  defp cast_map_to_struct(map, struct_module) when is_map(map) and is_atom(struct_module) do
    with {:ok, casted} <-
           Ash.Type.cast_input(Ash.Type.Struct, map, instance_of: struct_module),
         {:ok, constrained} <-
           Ash.Type.apply_constraints(Ash.Type.Struct, casted, instance_of: struct_module) do
      constrained
    else
      {:error, error} -> throw(error)
      :error -> throw("is invalid")
    end
  end

  # Returns %AshApiSpec.Type{} for the field, using spec data when available
  defp get_input_field_type(action, resource, field_key, resource_lookups) do
    case get_action_argument(action, field_key) do
      nil ->
        get_accepted_attribute_type(resource, field_key, resource_lookups)

      arg ->
        resolve_arg_type(arg)
    end
  end

  defp get_action_argument(action, field_key) do
    Enum.find(action.arguments, fn arg ->
      Map.get(arg, :public?, true) && arg.name == field_key
    end)
  end

  # Resolve argument type to %AshApiSpec.Type{}
  defp resolve_arg_type(%{type: %AshApiSpec.Type{} = spec_type}), do: spec_type

  defp resolve_arg_type(%{type: type, constraints: constraints}) when is_atom(type) do
    AshApiSpec.Generator.TypeResolver.resolve(type, constraints || [])
  end

  defp resolve_arg_type(%{type: {:array, _} = type, constraints: constraints}) do
    AshApiSpec.Generator.TypeResolver.resolve(type, constraints || [])
  end

  defp resolve_arg_type(%{type: type}) when is_atom(type) do
    AshApiSpec.Generator.TypeResolver.resolve(type, [])
  end

  defp resolve_arg_type(_), do: nil

  # Get accepted attribute type from resource_lookups or Ash introspection
  defp get_accepted_attribute_type(resource, field_key, resource_lookups)
       when is_map(resource_lookups) do
    case AshApiSpec.get_field(resource_lookups, resource, field_key) do
      %AshApiSpec.Field{type: type} -> type
      nil -> get_accepted_attribute_type_from_ash(resource, field_key)
    end
  end

  defp get_accepted_attribute_type(resource, field_key, _nil_lookups) do
    get_accepted_attribute_type_from_ash(resource, field_key)
  end

  defp get_accepted_attribute_type_from_ash(resource, field_key) do
    case Ash.Resource.Info.attribute(resource, field_key) do
      nil ->
        nil

      attr ->
        AshApiSpec.Generator.TypeResolver.resolve(attr.type, attr.constraints || [])
    end
  end
end
