# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.FieldProcessing.TypeProcessors.RelationshipProcessor do
  @moduledoc """
  Processes relationship fields, loading related resources with their requested fields.
  """

  @doc """
  Processes a relationship field with nested field selection.

  ## Parameters

  - `resource` - The current resource
  - `rel_name` - The relationship name
  - `nested_fields` - The fields to select from the related resource
  - `path` - The current path in the field hierarchy
  - `select` - The current select list
  - `load` - The current load list
  - `template` - The current extraction template

  ## Returns

  `{select, new_load, new_template}` tuple with the relationship added to load
  """
  def process_relationship(resource, rel_name, nested_fields, path, select, load, template) do
    relationship = Ash.Resource.Info.relationship(resource, rel_name)
    dest_resource = relationship && relationship.destination

    if dest_resource && AshTypescript.Resource.Info.typescript_resource?(dest_resource) do
      # Forward to process_nested_resource_fields which will be in FieldProcessor
      # to avoid circular dependencies
      {dest_resource, rel_name, nested_fields, path, select, load, template}
    else
      throw({:unknown_field, rel_name, resource, path})
    end
  end
end
