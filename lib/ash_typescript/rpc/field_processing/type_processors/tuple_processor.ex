# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.FieldProcessing.TypeProcessors.TupleProcessor do
  @moduledoc """
  Processes tuple fields with positional field selection.

  Tuples are fixed-size collections with named positions, similar to structs
  but ordered.
  """

  alias AshTypescript.Rpc.FieldProcessing.{Utilities, Validator}

  @doc """
  Processes a tuple field with nested field selection.

  ## Parameters

  - `resource` - The parent resource
  - `field_name` - The tuple field name
  - `nested_fields` - The fields to select from the tuple
  - `path` - Current path in field hierarchy
  - `select`, `load`, `template` - Current processing state
  - `process_fields_fn` - Function to recursively process nested fields

  ## Returns

  `{new_select, load, new_template}` tuple
  """
  def process_tuple_type(
        resource,
        field_name,
        nested_fields,
        path,
        select,
        load,
        template,
        process_fields_fn
      ) do
    Validator.validate_non_empty_fields(nested_fields, field_name, path, "Type")

    attribute = Ash.Resource.Info.attribute(resource, field_name)
    new_path = path ++ [field_name]

    {[], [], template_items} =
      process_tuple_fields(attribute.constraints, nested_fields, new_path, process_fields_fn)

    new_select = select ++ [field_name]

    {new_select, load, template ++ [{field_name, template_items}]}
  end

  @doc """
  Processes the fields within a tuple type.

  Tuple fields are positional and include an index in the template.
  """
  def process_tuple_fields(constraints, requested_fields, path, process_fields_fn) do
    Validator.check_for_duplicate_fields(requested_fields, path)
    field_specs = Keyword.get(constraints, :fields, [])
    field_names = Enum.map(field_specs, &elem(&1, 0))

    Enum.reduce(requested_fields, {[], [], []}, fn field, {select, load, template} ->
      field = if is_binary(field), do: String.to_existing_atom(field), else: field

      case field do
        field_name when is_atom(field_name) ->
          if Keyword.has_key?(field_specs, field_name) do
            index = Enum.find_index(field_names, &(&1 == field_name))
            {select, load, template ++ [%{field_name: field_name, index: index}]}
          else
            field_path = Utilities.build_field_path(path, field_name)
            throw({:unknown_field, field_name, "tuple", field_path})
          end

        %{} = field_map ->
          # Handle nested field selection for complex types within tuples
          Enum.reduce(field_map, {select, load, template}, fn {field_name, nested_fields},
                                                              {s, l, t} ->
            if Keyword.has_key?(field_specs, field_name) do
              field_spec = Keyword.get(field_specs, field_name)
              field_type = Keyword.get(field_spec, :type)
              field_constraints = Keyword.get(field_spec, :constraints, [])

              # Determine the return type for this field
              field_return_type = {:ash_type, field_type, field_constraints}
              new_path = path ++ [field_name]

              # Process the nested fields based on the field's type
              {_nested_select, _nested_load, nested_template} =
                process_fields_fn.(field_return_type, nested_fields, new_path)

              # For tuple fields, we don't need to add to select/load, just template
              {s, l, t ++ [{field_name, nested_template}]}
            else
              field_path = Utilities.build_field_path(path, field_name)
              throw({:unknown_field, field_name, "tuple", field_path})
            end
          end)
      end
    end)
  end
end
