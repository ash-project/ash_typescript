# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.TypeGenerators.RestrictedSchema do
  @moduledoc """
  Generates restricted resource schemas based on allowed_loads/denied_loads options.

  When an RPC action has load restrictions, this module generates action-specific
  TypeScript schema types that only expose allowed fields, providing compile-time
  type safety for field selection.

  Supports nested restrictions on:
  - Relationships (e.g., `denied_loads: [user: [:todos]]`)
  - Embedded resources (e.g., `denied_loads: [metadata: [:related_user]]`)
  - Union attributes (e.g., `denied_loads: [content: [:author]]`)
  """

  import AshTypescript.Helpers

  alias AshTypescript.Codegen.Helpers
  alias AshTypescript.TypeSystem.Introspection

  @doc """
  Checks if an RPC action has load restrictions configured.
  """
  def has_load_restrictions?(rpc_action) do
    not is_nil(Map.get(rpc_action, :allowed_loads)) or
      not is_nil(Map.get(rpc_action, :denied_loads))
  end

  @doc """
  Returns the schema reference and optional schema definition for an RPC action.

  If the action has load restrictions, returns `{schema_definition, schema_name}`.
  If no restrictions, returns `{nil, base_resource_schema_name}`.

  ## Parameters

    * `resource` - The Ash resource module
    * `rpc_action` - The RPC action configuration struct
    * `rpc_action_name_pascal` - The PascalCase name of the RPC action

  ## Returns

    * `{schema_definition, schema_reference}` where:
      - `schema_definition` is a string with TypeScript type def or nil if using base schema
      - `schema_reference` is the TypeScript type name to use in Fields type
  """
  def get_schema_and_reference(resource, rpc_action, rpc_action_name_pascal) do
    resource_name = Helpers.build_resource_type_name(resource)
    base_schema = "#{resource_name}ResourceSchema"

    allow_only = Map.get(rpc_action, :allowed_loads)
    deny = Map.get(rpc_action, :denied_loads)

    cond do
      not is_nil(deny) ->
        schema_name = "#{rpc_action_name_pascal}Schema"
        schema_def = generate_deny_schema(resource, deny, schema_name, base_schema)
        {schema_def, schema_name}

      not is_nil(allow_only) ->
        schema_name = "#{rpc_action_name_pascal}Schema"
        schema_def = generate_allow_only_schema(resource, allow_only, schema_name, base_schema)
        {schema_def, schema_name}

      true ->
        {nil, base_schema}
    end
  end

  @doc """
  Returns the TypeScript schema reference for an RPC action (without generating definition).

  Useful when the schema definition is generated separately.
  """
  def get_schema_reference(resource, rpc_action, rpc_action_name_pascal) do
    resource_name = Helpers.build_resource_type_name(resource)

    if has_load_restrictions?(rpc_action) do
      "#{rpc_action_name_pascal}Schema"
    else
      "#{resource_name}ResourceSchema"
    end
  end

  defp generate_deny_schema(resource, denied_loads, schema_name, base_schema) do
    {flat_denies, nested_denies} = partition_restrictions(denied_loads)

    if Enum.empty?(nested_denies) do
      generate_simple_deny_schema(flat_denies, schema_name, base_schema)
    else
      generate_nested_deny_schema(resource, flat_denies, nested_denies, schema_name, base_schema)
    end
  end

  defp generate_simple_deny_schema(denied_fields, schema_name, base_schema) do
    formatted_fields = format_fields_for_typescript(denied_fields)

    """
    type #{schema_name} = Omit<#{base_schema}, #{formatted_fields}>;
    """
  end

  defp generate_nested_deny_schema(
         resource,
         flat_denies,
         nested_denies,
         schema_name,
         base_schema
       ) do
    {nested_schema_defs, field_overrides} =
      nested_denies
      |> Enum.map(fn {field_name, nested_fields} ->
        process_nested_deny_field(resource, field_name, nested_fields, schema_name)
      end)
      |> Enum.unzip()

    nested_schemas =
      nested_schema_defs |> List.flatten() |> Enum.reject(&(&1 == "")) |> Enum.join("\n")

    overrides = field_overrides |> Enum.reject(&is_nil/1)

    all_fields_to_omit = flat_denies ++ Enum.map(overrides, fn {field_name, _} -> field_name end)

    if Enum.empty?(all_fields_to_omit) and Enum.empty?(overrides) do
      # Edge case: only nested restrictions, no flat denies
      override_fields = generate_override_fields(overrides)

      """
      #{nested_schemas}
      type #{schema_name} = #{base_schema} & {
      #{override_fields}
      };
      """
    else
      formatted_omits = format_fields_for_typescript(all_fields_to_omit)
      override_fields = generate_override_fields(overrides)

      if Enum.empty?(overrides) do
        """
        #{nested_schemas}
        type #{schema_name} = Omit<#{base_schema}, #{formatted_omits}>;
        """
      else
        """
        #{nested_schemas}
        type #{schema_name} = Omit<#{base_schema}, #{formatted_omits}> & {
        #{override_fields}
        };
        """
      end
    end
  end

  defp process_nested_deny_field(resource, field_name, nested_fields, schema_name) do
    case resolve_field_info(resource, field_name) do
      {:relationship, rel} ->
        process_nested_deny_relationship(resource, rel, nested_fields, schema_name)

      {:embedded, attr, embedded_resource} ->
        process_nested_deny_embedded(
          resource,
          attr,
          embedded_resource,
          nested_fields,
          schema_name
        )

      {:union, attr, union_types} ->
        process_nested_deny_union(resource, attr, union_types, nested_fields, schema_name)

      :not_found ->
        {"", nil}
    end
  end

  defp process_nested_deny_relationship(resource, rel, nested_fields, schema_name) do
    nested_resource_name = Helpers.build_resource_type_name(rel.destination)
    nested_base = "#{nested_resource_name}ResourceSchema"
    nested_schema_name = "#{schema_name}#{snake_to_pascal_case(rel.name)}"

    nested_def =
      generate_deny_schema(rel.destination, nested_fields, nested_schema_name, nested_base)

    override = generate_relationship_override(resource, rel, nested_schema_name)

    {nested_def, {rel.name, override}}
  end

  defp process_nested_deny_embedded(resource, attr, embedded_resource, nested_fields, schema_name) do
    nested_resource_name = Helpers.build_resource_type_name(embedded_resource)
    nested_base = "#{nested_resource_name}ResourceSchema"
    nested_schema_name = "#{schema_name}#{snake_to_pascal_case(attr.name)}"

    nested_def =
      generate_deny_schema(embedded_resource, nested_fields, nested_schema_name, nested_base)

    override = generate_embedded_override(resource, attr, nested_schema_name)

    {nested_def, {attr.name, override}}
  end

  defp process_nested_deny_union(resource, attr, union_types, nested_fields, schema_name) do
    {member_schema_defs, member_overrides} =
      union_types
      |> Enum.map(fn {member_name, member_config} ->
        member_type = Keyword.get(member_config, :type)
        inner_type = unwrap_array_type(member_type)

        if is_atom(inner_type) and
             (Introspection.is_embedded_resource?(inner_type) or
                Ash.Resource.Info.resource?(inner_type)) do
          nested_resource_name = Helpers.build_resource_type_name(inner_type)
          nested_base = "#{nested_resource_name}ResourceSchema"

          member_schema_name =
            "#{schema_name}#{snake_to_pascal_case(attr.name)}#{snake_to_pascal_case(member_name)}"

          nested_def =
            generate_deny_schema(inner_type, nested_fields, member_schema_name, nested_base)

          {nested_def, {member_name, member_schema_name, member_type}}
        else
          {"", nil}
        end
      end)
      |> Enum.unzip()

    valid_member_overrides = Enum.reject(member_overrides, &is_nil/1)
    all_schema_defs = Enum.reject(member_schema_defs, &(&1 == ""))

    if Enum.empty?(valid_member_overrides) do
      {"", nil}
    else
      override = generate_union_override(resource, attr, union_types, valid_member_overrides)
      {all_schema_defs, {attr.name, override}}
    end
  end

  defp generate_allow_only_schema(resource, allowed_loads, schema_name, base_schema) do
    {flat_allows, nested_allows} = partition_restrictions(allowed_loads)
    all_loadable_fields = get_loadable_field_names(resource)

    if Enum.empty?(nested_allows) and Enum.empty?(flat_allows) do
      generate_simple_deny_schema(all_loadable_fields, schema_name, base_schema)
    else
      generate_nested_allow_only_schema(
        resource,
        flat_allows,
        nested_allows,
        all_loadable_fields,
        schema_name,
        base_schema
      )
    end
  end

  defp generate_nested_allow_only_schema(
         resource,
         flat_allows,
         nested_allows,
         all_loadable_fields,
         schema_name,
         base_schema
       ) do
    nested_field_names = Enum.map(nested_allows, fn {field_name, _} -> field_name end)

    # Process nested allows (with recursive restrictions)
    {nested_schema_defs, nested_overrides} =
      nested_allows
      |> Enum.map(fn {field_name, allowed_nested_fields} ->
        process_nested_allow_field(resource, field_name, allowed_nested_fields, schema_name)
      end)
      |> Enum.unzip()

    # Process flat allows - these use AttributesOnlySchema (no nested loads allowed)
    flat_overrides =
      flat_allows
      |> Enum.map(fn field_name ->
        process_flat_allow_field(resource, field_name)
      end)
      |> Enum.reject(&is_nil/1)

    nested_schemas =
      nested_schema_defs |> List.flatten() |> Enum.reject(&(&1 == "")) |> Enum.join("\n")

    all_overrides = Enum.reject(nested_overrides, &is_nil/1) ++ flat_overrides

    allowed_loadables = flat_allows ++ nested_field_names
    fields_to_omit = all_loadable_fields -- allowed_loadables
    all_fields_to_omit = fields_to_omit ++ nested_field_names ++ flat_allows

    formatted_omits = format_fields_for_typescript(all_fields_to_omit)
    override_fields = generate_override_fields(all_overrides)

    if Enum.empty?(all_overrides) do
      """
      #{nested_schemas}
      type #{schema_name} = Omit<#{base_schema}, #{formatted_omits}>;
      """
    else
      """
      #{nested_schemas}
      type #{schema_name} = Omit<#{base_schema}, #{formatted_omits}> & {
      #{override_fields}
      };
      """
    end
  end

  defp process_flat_allow_field(resource, field_name) do
    case resolve_field_info(resource, field_name) do
      {:relationship, rel} ->
        generate_attributes_only_relationship_override(resource, rel)

      {:embedded, attr, embedded_resource} ->
        generate_attributes_only_embedded_override(resource, attr, embedded_resource)

      {:union, attr, union_types} ->
        generate_attributes_only_union_override(resource, attr, union_types)

      :not_found ->
        nil
    end
  end

  defp generate_attributes_only_relationship_override(resource, rel) do
    formatted_name = format_client_field_name(resource, rel.name)
    dest_name = Helpers.build_resource_type_name(rel.destination)

    resource_type =
      if rel.type in [:has_many, :many_to_many] do
        "#{dest_name}AttributesOnlySchema"
      else
        if Map.get(rel, :allow_nil?, true) do
          "#{dest_name}AttributesOnlySchema | null"
        else
          "#{dest_name}AttributesOnlySchema"
        end
      end

    metadata =
      case rel.type do
        :has_many ->
          "{ __type: \"Relationship\"; __array: true; __resource: #{resource_type}; }"

        :many_to_many ->
          "{ __type: \"Relationship\"; __array: true; __resource: #{resource_type}; }"

        _ ->
          "{ __type: \"Relationship\"; __resource: #{resource_type}; }"
      end

    {rel.name, "#{formatted_name}: #{metadata}"}
  end

  defp generate_attributes_only_embedded_override(resource, attr, _embedded_resource) do
    formatted_name = format_client_field_name(resource, attr.name)
    inner_type = unwrap_array_type(attr.type)
    embedded_name = Helpers.build_resource_type_name(inner_type)
    is_array = match?({:array, _}, attr.type)

    resource_type =
      if Map.get(attr, :allow_nil?, true) do
        "#{embedded_name}AttributesOnlySchema | null"
      else
        "#{embedded_name}AttributesOnlySchema"
      end

    metadata =
      if is_array do
        "{ __type: \"Relationship\"; __array: true; __resource: #{resource_type}; }"
      else
        "{ __type: \"Relationship\"; __resource: #{resource_type}; }"
      end

    {attr.name, "#{formatted_name}: #{metadata}"}
  end

  defp generate_attributes_only_union_override(resource, attr, union_types) do
    formatted_name = format_client_field_name(resource, attr.name)
    is_array = match?({:array, _}, attr.type)

    member_type_strs =
      union_types
      |> Enum.map(fn {member_name, member_config} ->
        member_type = Keyword.get(member_config, :type)
        inner_type = unwrap_array_type(member_type)

        if is_atom(inner_type) and
             (Introspection.is_embedded_resource?(inner_type) or
                Ash.Resource.Info.resource?(inner_type)) do
          resource_name = Helpers.build_resource_type_name(inner_type)
          formatted_member = format_output_field(member_name)
          member_is_array = match?({:array, _}, member_type)

          if member_is_array do
            "{ #{formatted_member}: { __type: \"Relationship\"; __array: true; __resource: #{resource_name}AttributesOnlySchema; } }"
          else
            "{ #{formatted_member}: { __type: \"Relationship\"; __resource: #{resource_name}AttributesOnlySchema; } }"
          end
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(member_type_strs) do
      nil
    else
      members_str = member_type_strs |> Enum.join(" | ")

      metadata =
        if is_array do
          "{ __type: \"Union\"; __array: true; __members: #{members_str}; }"
        else
          "{ __type: \"Union\"; __members: #{members_str}; }"
        end

      {attr.name, "#{formatted_name}: #{metadata}"}
    end
  end

  defp process_nested_allow_field(resource, field_name, allowed_nested_fields, schema_name) do
    case resolve_field_info(resource, field_name) do
      {:relationship, rel} ->
        process_nested_allow_relationship(resource, rel, allowed_nested_fields, schema_name)

      {:embedded, attr, embedded_resource} ->
        process_nested_allow_embedded(
          resource,
          attr,
          embedded_resource,
          allowed_nested_fields,
          schema_name
        )

      {:union, attr, union_types} ->
        process_nested_allow_union(
          resource,
          attr,
          union_types,
          allowed_nested_fields,
          schema_name
        )

      :not_found ->
        {"", nil}
    end
  end

  defp process_nested_allow_relationship(resource, rel, allowed_nested_fields, schema_name) do
    nested_resource_name = Helpers.build_resource_type_name(rel.destination)
    nested_base = "#{nested_resource_name}ResourceSchema"
    nested_schema_name = "#{schema_name}#{snake_to_pascal_case(rel.name)}"

    nested_def =
      generate_allow_only_schema(
        rel.destination,
        allowed_nested_fields,
        nested_schema_name,
        nested_base
      )

    override = generate_relationship_override(resource, rel, nested_schema_name)

    {nested_def, {rel.name, override}}
  end

  defp process_nested_allow_embedded(
         resource,
         attr,
         embedded_resource,
         allowed_nested_fields,
         schema_name
       ) do
    nested_resource_name = Helpers.build_resource_type_name(embedded_resource)
    nested_base = "#{nested_resource_name}ResourceSchema"
    nested_schema_name = "#{schema_name}#{snake_to_pascal_case(attr.name)}"

    nested_def =
      generate_allow_only_schema(
        embedded_resource,
        allowed_nested_fields,
        nested_schema_name,
        nested_base
      )

    override = generate_embedded_override(resource, attr, nested_schema_name)

    {nested_def, {attr.name, override}}
  end

  defp process_nested_allow_union(resource, attr, union_types, allowed_nested_fields, schema_name) do
    {member_schema_defs, member_overrides} =
      union_types
      |> Enum.map(fn {member_name, member_config} ->
        member_type = Keyword.get(member_config, :type)
        inner_type = unwrap_array_type(member_type)

        if is_atom(inner_type) and
             (Introspection.is_embedded_resource?(inner_type) or
                Ash.Resource.Info.resource?(inner_type)) do
          nested_resource_name = Helpers.build_resource_type_name(inner_type)
          nested_base = "#{nested_resource_name}ResourceSchema"

          member_schema_name =
            "#{schema_name}#{snake_to_pascal_case(attr.name)}#{snake_to_pascal_case(member_name)}"

          nested_def =
            generate_allow_only_schema(
              inner_type,
              allowed_nested_fields,
              member_schema_name,
              nested_base
            )

          {nested_def, {member_name, member_schema_name, member_type}}
        else
          {"", nil}
        end
      end)
      |> Enum.unzip()

    valid_member_overrides = Enum.reject(member_overrides, &is_nil/1)
    all_schema_defs = Enum.reject(member_schema_defs, &(&1 == ""))

    if Enum.empty?(valid_member_overrides) do
      {"", nil}
    else
      override = generate_union_override(resource, attr, union_types, valid_member_overrides)
      {all_schema_defs, {attr.name, override}}
    end
  end

  defp resolve_field_info(resource, field_name) do
    rel = Ash.Resource.Info.relationship(resource, field_name)

    if rel do
      {:relationship, rel}
    else
      attr = Ash.Resource.Info.attribute(resource, field_name)

      if attr do
        resolve_attribute_info(attr)
      else
        calc = Ash.Resource.Info.calculation(resource, field_name)

        if calc do
          resolve_calculation_info(calc)
        else
          :not_found
        end
      end
    end
  end

  defp resolve_attribute_info(attr) do
    inner_type = unwrap_array_type(attr.type)

    cond do
      is_atom(inner_type) and Introspection.is_embedded_resource?(inner_type) ->
        {:embedded, attr, inner_type}

      inner_type == Ash.Type.Union ->
        union_types = get_union_types(attr)
        {:union, attr, union_types}

      true ->
        :not_found
    end
  end

  defp resolve_calculation_info(calc) do
    inner_type = unwrap_array_type(calc.type)

    cond do
      is_atom(inner_type) and Introspection.is_embedded_resource?(inner_type) ->
        {:embedded, calc, inner_type}

      inner_type == Ash.Type.Union ->
        union_types = get_union_types_from_calc(calc)
        {:union, calc, union_types}

      is_atom(inner_type) and Ash.Resource.Info.resource?(inner_type) ->
        {:embedded, calc, inner_type}

      true ->
        :not_found
    end
  end

  defp get_union_types(attr) do
    Introspection.get_union_types_from_constraints(attr.type, attr.constraints)
  end

  defp get_union_types_from_calc(calc) do
    Introspection.get_union_types_from_constraints(calc.type, calc.constraints)
  end

  defp unwrap_array_type({:array, inner}), do: inner
  defp unwrap_array_type(type), do: type

  defp generate_relationship_override(resource, rel, nested_schema_name) do
    formatted_name = format_client_field_name(resource, rel.name)

    resource_type =
      if rel.type in [:has_many, :many_to_many] do
        nested_schema_name
      else
        if Map.get(rel, :allow_nil?, true) do
          "#{nested_schema_name} | null"
        else
          nested_schema_name
        end
      end

    metadata =
      case rel.type do
        :has_many ->
          "{ __type: \"Relationship\"; __array: true; __resource: #{resource_type}; }"

        :many_to_many ->
          "{ __type: \"Relationship\"; __array: true; __resource: #{resource_type}; }"

        _ ->
          "{ __type: \"Relationship\"; __resource: #{resource_type}; }"
      end

    "#{formatted_name}: #{metadata}"
  end

  defp generate_embedded_override(resource, attr, nested_schema_name) do
    formatted_name = format_client_field_name(resource, attr.name)
    is_array = match?({:array, _}, attr.type)

    resource_type =
      if is_array do
        nested_schema_name
      else
        if Map.get(attr, :allow_nil?, true) do
          "#{nested_schema_name} | null"
        else
          nested_schema_name
        end
      end

    metadata =
      if is_array do
        "{ __type: \"Relationship\"; __array: true; __resource: #{resource_type}; }"
      else
        "{ __type: \"Relationship\"; __resource: #{resource_type}; }"
      end

    "#{formatted_name}: #{metadata}"
  end

  defp generate_union_override(resource, attr, union_types, member_overrides) do
    formatted_name = format_client_field_name(resource, attr.name)
    is_array = match?({:array, _}, attr.type)

    member_type_strs =
      union_types
      |> Enum.map(fn {member_name, member_config} ->
        member_type = Keyword.get(member_config, :type)

        case Enum.find(member_overrides, fn {name, _, _} -> name == member_name end) do
          {_, schema_name, _member_type} ->
            generate_union_member_metadata(member_name, schema_name, member_type)

          nil ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(member_type_strs) do
      nil
    else
      members_str = member_type_strs |> Enum.join(" | ")

      metadata =
        if is_array do
          "{ __type: \"Union\"; __array: true; __members: #{members_str}; }"
        else
          "{ __type: \"Union\"; __members: #{members_str}; }"
        end

      "#{formatted_name}: #{metadata}"
    end
  end

  defp generate_union_member_metadata(member_name, schema_name, member_type) do
    is_array = match?({:array, _}, member_type)
    formatted_member_name = format_output_field(member_name)

    if is_array do
      "{ #{formatted_member_name}: { __type: \"Relationship\"; __array: true; __resource: #{schema_name}; } }"
    else
      "{ #{formatted_member_name}: { __type: \"Relationship\"; __resource: #{schema_name}; } }"
    end
  end

  defp generate_override_fields(overrides) do
    Enum.map_join(overrides, "\n", fn {_field_name, override_str} -> "  #{override_str};" end)
  end

  defp partition_restrictions(restrictions) do
    flat =
      restrictions
      |> Enum.filter(&is_atom/1)

    nested =
      restrictions
      |> Enum.filter(&is_tuple/1)

    {flat, nested}
  end

  defp get_loadable_field_names(resource) do
    relationships =
      resource
      |> Ash.Resource.Info.public_relationships()
      |> Enum.map(& &1.name)

    calculations =
      resource
      |> Ash.Resource.Info.public_calculations()
      |> Enum.map(& &1.name)

    aggregates =
      resource
      |> Ash.Resource.Info.public_aggregates()
      |> Enum.map(& &1.name)

    relationships ++ calculations ++ aggregates
  end

  defp format_fields_for_typescript(fields) when fields == [], do: "never"

  defp format_fields_for_typescript(fields) do
    Enum.map_join(fields, " | ", &"'#{format_output_field(&1)}'")
  end

  defp format_client_field_name(resource, field_name) do
    AshTypescript.FieldFormatter.format_field_for_client(
      field_name,
      resource,
      AshTypescript.Rpc.output_field_formatter()
    )
  end
end
