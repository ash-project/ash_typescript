# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
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
  def get_schema_and_reference(resource, rpc_action, rpc_action_name_pascal, resource_lookup) do
    resource_name = Helpers.build_resource_type_name(resource)
    base_schema = "#{resource_name}ResourceSchema"

    allow_only = Map.get(rpc_action, :allowed_loads)
    deny = Map.get(rpc_action, :denied_loads)

    if is_nil(deny) and is_nil(allow_only) do
      {nil, base_schema}
    else
      cond do
        not is_nil(deny) ->
          schema_name = "#{rpc_action_name_pascal}Schema"

          schema_def =
            generate_deny_schema(resource, deny, schema_name, base_schema, resource_lookup)

          {schema_def, schema_name}

        not is_nil(allow_only) ->
          schema_name = "#{rpc_action_name_pascal}Schema"

          schema_def =
            generate_allow_only_schema(
              resource,
              allow_only,
              schema_name,
              base_schema,
              resource_lookup
            )

          {schema_def, schema_name}
      end
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

  defp generate_deny_schema(resource, denied_loads, schema_name, base_schema, resource_lookup) do
    {flat_denies, nested_denies} = partition_restrictions(denied_loads)

    if Enum.empty?(nested_denies) do
      generate_simple_deny_schema(flat_denies, schema_name, base_schema)
    else
      generate_nested_deny_schema(
        resource,
        flat_denies,
        nested_denies,
        schema_name,
        base_schema,
        resource_lookup
      )
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
         base_schema,
         resource_lookup
       ) do
    {nested_schema_defs, field_overrides} =
      nested_denies
      |> Enum.map(fn {field_name, nested_fields} ->
        process_nested_deny_field(
          resource,
          field_name,
          nested_fields,
          schema_name,
          resource_lookup
        )
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

  defp process_nested_deny_field(
         resource,
         field_name,
         nested_fields,
         schema_name,
         resource_lookup
       ) do
    case resolve_field_info(resource, field_name, resource_lookup) do
      {:relationship, rel} ->
        process_nested_deny_relationship(
          resource,
          rel,
          nested_fields,
          schema_name,
          resource_lookup
        )

      {:embedded, attr, embedded_resource} ->
        process_nested_deny_embedded(
          resource,
          attr,
          embedded_resource,
          nested_fields,
          schema_name,
          resource_lookup
        )

      {:union, attr, union_types} ->
        process_nested_deny_union(
          resource,
          attr,
          union_types,
          nested_fields,
          schema_name,
          resource_lookup
        )

      :not_found ->
        {"", nil}
    end
  end

  defp process_nested_deny_relationship(
         resource,
         rel,
         nested_fields,
         schema_name,
         resource_lookup
       ) do
    nested_resource_name = Helpers.build_resource_type_name(rel.destination)
    nested_base = "#{nested_resource_name}ResourceSchema"
    nested_schema_name = "#{schema_name}#{snake_to_pascal_case(rel.name)}"

    nested_def =
      generate_deny_schema(
        rel.destination,
        nested_fields,
        nested_schema_name,
        nested_base,
        resource_lookup
      )

    override = generate_relationship_override(resource, rel, nested_schema_name)

    {nested_def, {rel.name, override}}
  end

  defp process_nested_deny_embedded(
         resource,
         attr,
         embedded_resource,
         nested_fields,
         schema_name,
         resource_lookup
       ) do
    nested_resource_name = Helpers.build_resource_type_name(embedded_resource)
    nested_base = "#{nested_resource_name}ResourceSchema"
    nested_schema_name = "#{schema_name}#{snake_to_pascal_case(attr.name)}"

    nested_def =
      generate_deny_schema(
        embedded_resource,
        nested_fields,
        nested_schema_name,
        nested_base,
        resource_lookup
      )

    override = generate_embedded_override(resource, attr, nested_schema_name)

    {nested_def, {attr.name, override}}
  end

  defp process_nested_deny_union(
         resource,
         attr,
         union_types,
         nested_fields,
         schema_name,
         resource_lookup
       ) do
    {member_schema_defs, member_overrides} =
      union_types
      |> Enum.map(fn {member_name, member_config} ->
        member_type = Keyword.get(member_config, :type)
        inner_type = unwrap_array_type(member_type)

        if is_atom(inner_type) and Map.has_key?(resource_lookup, inner_type) do
          nested_resource_name = Helpers.build_resource_type_name(inner_type)
          nested_base = "#{nested_resource_name}ResourceSchema"

          member_schema_name =
            "#{schema_name}#{snake_to_pascal_case(attr.name)}#{snake_to_pascal_case(member_name)}"

          nested_def =
            generate_deny_schema(
              inner_type,
              nested_fields,
              member_schema_name,
              nested_base,
              resource_lookup
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

  defp generate_allow_only_schema(
         resource,
         allowed_loads,
         schema_name,
         base_schema,
         resource_lookup
       ) do
    {flat_allows, nested_allows} = partition_restrictions(allowed_loads)
    all_loadable_fields = get_loadable_field_names(resource, resource_lookup)

    if Enum.empty?(nested_allows) and Enum.empty?(flat_allows) do
      generate_simple_deny_schema(all_loadable_fields, schema_name, base_schema)
    else
      generate_nested_allow_only_schema(
        resource,
        flat_allows,
        nested_allows,
        all_loadable_fields,
        schema_name,
        base_schema,
        resource_lookup
      )
    end
  end

  defp generate_nested_allow_only_schema(
         resource,
         flat_allows,
         nested_allows,
         all_loadable_fields,
         schema_name,
         base_schema,
         resource_lookup
       ) do
    nested_field_names = Enum.map(nested_allows, fn {field_name, _} -> field_name end)

    {nested_schema_defs, nested_overrides} =
      nested_allows
      |> Enum.map(fn {field_name, allowed_nested_fields} ->
        process_nested_allow_field(
          resource,
          field_name,
          allowed_nested_fields,
          schema_name,
          resource_lookup
        )
      end)
      |> Enum.unzip()

    # Flat allows use AttributesOnlySchema (no nested loads allowed)
    flat_overrides =
      flat_allows
      |> Enum.map(fn field_name ->
        process_flat_allow_field(resource, field_name, resource_lookup)
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

  defp process_flat_allow_field(resource, field_name, resource_lookup) do
    case resolve_field_info(resource, field_name, resource_lookup) do
      {:relationship, rel} ->
        generate_attributes_only_relationship_override(resource, rel)

      {:embedded, attr, embedded_resource} ->
        generate_attributes_only_embedded_override(resource, attr, embedded_resource)

      {:union, attr, union_types} ->
        generate_attributes_only_union_override(resource, attr, union_types, resource_lookup)

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

  defp generate_attributes_only_embedded_override(resource, attr, embedded_resource) do
    formatted_name = format_client_field_name(resource, attr.name)
    embedded_name = Helpers.build_resource_type_name(embedded_resource)
    is_array = api_field_is_array?(attr)

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

  defp generate_attributes_only_union_override(resource, attr, union_types, resource_lookup) do
    formatted_name = format_client_field_name(resource, attr.name)
    is_array = api_field_is_array?(attr)

    member_type_strs =
      union_types
      |> Enum.map(fn {member_name, member_config} ->
        member_type = Keyword.get(member_config, :type)
        inner_type = unwrap_array_type(member_type)

        if is_atom(inner_type) and Map.has_key?(resource_lookup, inner_type) do
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

  defp process_nested_allow_field(
         resource,
         field_name,
         allowed_nested_fields,
         schema_name,
         resource_lookup
       ) do
    case resolve_field_info(resource, field_name, resource_lookup) do
      {:relationship, rel} ->
        process_nested_allow_relationship(
          resource,
          rel,
          allowed_nested_fields,
          schema_name,
          resource_lookup
        )

      {:embedded, attr, embedded_resource} ->
        process_nested_allow_embedded(
          resource,
          attr,
          embedded_resource,
          allowed_nested_fields,
          schema_name,
          resource_lookup
        )

      {:union, attr, union_types} ->
        process_nested_allow_union(
          resource,
          attr,
          union_types,
          allowed_nested_fields,
          schema_name,
          resource_lookup
        )

      :not_found ->
        {"", nil}
    end
  end

  defp process_nested_allow_relationship(
         resource,
         rel,
         allowed_nested_fields,
         schema_name,
         resource_lookup
       ) do
    nested_resource_name = Helpers.build_resource_type_name(rel.destination)
    nested_base = "#{nested_resource_name}ResourceSchema"
    nested_schema_name = "#{schema_name}#{snake_to_pascal_case(rel.name)}"

    nested_def =
      generate_allow_only_schema(
        rel.destination,
        allowed_nested_fields,
        nested_schema_name,
        nested_base,
        resource_lookup
      )

    override = generate_relationship_override(resource, rel, nested_schema_name)

    {nested_def, {rel.name, override}}
  end

  defp process_nested_allow_embedded(
         resource,
         attr,
         embedded_resource,
         allowed_nested_fields,
         schema_name,
         resource_lookup
       ) do
    nested_resource_name = Helpers.build_resource_type_name(embedded_resource)
    nested_base = "#{nested_resource_name}ResourceSchema"
    nested_schema_name = "#{schema_name}#{snake_to_pascal_case(attr.name)}"

    nested_def =
      generate_allow_only_schema(
        embedded_resource,
        allowed_nested_fields,
        nested_schema_name,
        nested_base,
        resource_lookup
      )

    override = generate_embedded_override(resource, attr, nested_schema_name)

    {nested_def, {attr.name, override}}
  end

  defp process_nested_allow_union(
         resource,
         attr,
         union_types,
         allowed_nested_fields,
         schema_name,
         resource_lookup
       ) do
    {member_schema_defs, member_overrides} =
      union_types
      |> Enum.map(fn {member_name, member_config} ->
        member_type = Keyword.get(member_config, :type)
        inner_type = unwrap_array_type(member_type)

        if is_atom(inner_type) and Map.has_key?(resource_lookup, inner_type) do
          nested_resource_name = Helpers.build_resource_type_name(inner_type)
          nested_base = "#{nested_resource_name}ResourceSchema"

          member_schema_name =
            "#{schema_name}#{snake_to_pascal_case(attr.name)}#{snake_to_pascal_case(member_name)}"

          nested_def =
            generate_allow_only_schema(
              inner_type,
              allowed_nested_fields,
              member_schema_name,
              nested_base,
              resource_lookup
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

  defp resolve_field_info(resource, field_name, resource_lookup) do
    api_resource = AshApiSpec.get_resource!(resource_lookup, resource)
    rel = AshApiSpec.Resource.get_relationship(api_resource, field_name)

    if rel do
      {:relationship, rel}
    else
      field = AshApiSpec.Resource.get_field(api_resource, field_name)

      if field do
        resolve_field_type_info(field)
      else
        :not_found
      end
    end
  end

  defp resolve_field_type_info(%AshApiSpec.Field{} = field) do
    api_type = resolve_inner_api_type(field.type)

    cond do
      api_type.kind in [:embedded_resource, :resource] ->
        {:embedded, field, api_type.resource_module}

      api_type.kind == :union ->
        union_types = Keyword.get(api_type.constraints || [], :types, [])
        {:union, field, union_types}

      true ->
        :not_found
    end
  end

  # Unwraps :array types to get the inner AshApiSpec.Type, otherwise returns the type as-is.
  defp resolve_inner_api_type(%AshApiSpec.Type{kind: :array, item_type: item_type}),
    do: item_type

  defp resolve_inner_api_type(%AshApiSpec.Type{} = type), do: type

  # Checks if an AshApiSpec.Field has an array type.
  defp api_field_is_array?(%AshApiSpec.Field{type: %AshApiSpec.Type{kind: :array}}), do: true
  defp api_field_is_array?(%AshApiSpec.Field{}), do: false

  # Unwraps raw Ash array types (used for union member type processing).
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
    is_array = api_field_is_array?(attr)

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
    is_array = api_field_is_array?(attr)

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

  defp get_loadable_field_names(resource, resource_lookup) do
    api_resource = AshApiSpec.get_resource!(resource_lookup, resource)

    relationships =
      api_resource
      |> AshApiSpec.Resource.all_relationships()
      |> Enum.map(& &1.name)

    calculations =
      api_resource
      |> AshApiSpec.Resource.fields_by_kind(:calculation)
      |> Enum.map(& &1.name)

    aggregates =
      api_resource
      |> AshApiSpec.Resource.fields_by_kind(:aggregate)
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
