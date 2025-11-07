# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.FieldProcessing.TypeProcessors.EmbeddedProcessor do
  @moduledoc """
  Processes embedded resource fields with nested field selection.

  Embedded resources are resources that are stored directly within parent resources,
  similar to relationships but without separate database storage.
  """

  alias AshTypescript.Rpc.FieldProcessing.{Utilities, Validator}

  @doc """
  Processes an embedded resource field with nested field selection.

  ## Parameters

  - `resource` - The parent resource
  - `field_name` - The embedded resource field name
  - `nested_fields` - The fields to select from the embedded resource
  - `path` - The current path in the field hierarchy
  - `select` - The current select list
  - `load` - The current load list
  - `template` - The current extraction template

  ## Returns

  `{embedded_resource, new_path, nested_fields, select, load, template}` tuple
  with information needed for further processing
  """
  def process_embedded_resource(
        resource,
        field_name,
        nested_fields,
        path,
        select,
        load,
        template
      ) do
    Validator.validate_non_empty_fields(nested_fields, field_name, path, "Relationship")

    attribute = Ash.Resource.Info.attribute(resource, field_name)
    embedded_resource = Utilities.extract_embedded_resource_type(attribute.type)

    new_path = path ++ [field_name]
    new_select = select ++ [field_name]

    # Return the embedded resource and new path for the caller to process
    {embedded_resource, new_path, nested_fields, new_select, load, template, field_name}
  end
end
