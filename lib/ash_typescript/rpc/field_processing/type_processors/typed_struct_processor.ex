# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.FieldProcessing.TypeProcessors.TypedStructProcessor do
  @moduledoc """
  Processes TypedStruct fields with nested field selection.

  TypedStructs are Elixir structs with typed fields, similar to embedded resources
  but lighter weight.
  """

  alias AshTypescript.Rpc.FieldProcessing.{Utilities, Validator}

  @doc """
  Processes a TypedStruct field with nested field selection.

  Supports field name mapping if the TypedStruct module exports typescript_field_names/0.
  """
  def process_typed_struct(
        resource,
        field_name,
        nested_fields,
        path,
        select,
        load,
        template,
        process_fields_fn
      ) do
    Validator.validate_non_empty_fields(nested_fields, field_name, path, "TypedStruct")

    attribute = Ash.Resource.Info.attribute(resource, field_name)
    field_specs = Keyword.get(attribute.constraints, :fields, [])
    instance_of = Keyword.get(attribute.constraints, :instance_of)

    field_name_mappings =
      if instance_of && function_exported?(instance_of, :typescript_field_names, 0) do
        instance_of.typescript_field_names()
      else
        []
      end

    new_path = path ++ [field_name]

    {_field_names, template_items} =
      process_typed_struct_fields(
        nested_fields,
        field_specs,
        new_path,
        field_name_mappings,
        process_fields_fn
      )

    new_select = select ++ [field_name]

    {new_select, load, template ++ [{field_name, template_items}]}
  end

  @doc """
  Processes the fields within a TypedStruct.

  Handles field name mapping between TypeScript and Elixir names.
  """
  def process_typed_struct_fields(
        requested_fields,
        field_specs,
        path,
        field_name_mappings,
        process_fields_fn
      ) do
    Validator.check_for_duplicate_fields(requested_fields, path)

    reverse_mappings =
      Enum.into(field_name_mappings, %{}, fn {elixir_name, ts_name} ->
        {ts_name, elixir_name}
      end)

    {field_names, template_items} =
      Enum.reduce(requested_fields, {[], []}, fn field, {names, template} ->
        case field do
          field_atom when is_atom(field_atom) or is_binary(field_atom) ->
            field_atom =
              if is_binary(field_atom) do
                String.to_existing_atom(field_atom)
              else
                field_atom
              end

            elixir_field_name = Map.get(reverse_mappings, field_atom, field_atom)

            if Keyword.has_key?(field_specs, elixir_field_name) do
              {names ++ [elixir_field_name], template ++ [elixir_field_name]}
            else
              field_path = Utilities.build_field_path(path, field_atom)
              throw({:unknown_field, field_atom, "typed_struct", field_path})
            end

          %{} = field_map ->
            {new_names, new_template} =
              Enum.reduce(field_map, {names, template}, fn {field_name, nested_fields}, {n, t} ->
                elixir_field_name = Map.get(reverse_mappings, field_name, field_name)

                if Keyword.has_key?(field_specs, elixir_field_name) do
                  field_spec = Keyword.get(field_specs, elixir_field_name)
                  field_type = Keyword.get(field_spec, :type)
                  field_constraints = Keyword.get(field_spec, :constraints, [])
                  field_return_type = {:ash_type, field_type, field_constraints}
                  new_path = path ++ [elixir_field_name]

                  {_nested_select, _nested_load, nested_template} =
                    process_fields_fn.(field_return_type, nested_fields, new_path)

                  {n ++ [elixir_field_name], t ++ [{elixir_field_name, nested_template}]}
                else
                  field_path = Utilities.build_field_path(path, field_name)
                  throw({:unknown_field, field_name, "typed_struct", field_path})
                end
              end)

            {new_names, new_template}
        end
      end)

    {field_names, template_items}
  end
end
