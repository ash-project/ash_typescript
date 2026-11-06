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
  - Union members (e.g., `denied_loads: [content: [text: [:display_text]]]`)

  The schemas follow ash_rpc, which restricts loads (relationships,
  calculations, aggregates) and never attributes: a bare denied embedded or
  union attribute or member, and under `allowed_loads` every embedded or union
  attribute the entries don't name, keeps its attributes only, all the way
  down (`attributes_only_type/3`), and a restricted has_many / many_to_many
  keeps the base schema's query markers.
  """

  import AshTypescript.Helpers

  alias AshTypescript.Codegen.{ClientNames, Helpers, ResourceSchemas, TypeMapper}
  alias AshTypescript.Manifest.LoadPaths
  alias AshTypescript.NameValidation
  alias AshTypescript.Rpc.Codegen.FunctionNames
  alias AshTypescript.Rpc.Codegen.Helpers.EntrypointOptions

  @doc """
  Returns the schema reference and optional schema definition for an RPC action.

  If the action has load restrictions, returns `{schema_definition, schema_name}`.
  If no restrictions, returns `{nil, base_resource_schema_name}`.

  ## Parameters

    * `resource` - The Ash resource module
    * `rpc_action` - The RPC action configuration struct

  ## Returns

    * `{schema_definition, schema_reference}` where:
      - `schema_definition` is a string with TypeScript type def or nil if using base schema
      - `schema_reference` is the TypeScript type name to use in Fields type
  """
  def get_schema_and_reference(resource, rpc_action, resource_lookup) do
    resource_name = Helpers.build_resource_type_name(resource)
    base_schema = "#{resource_name}ResourceSchema"

    schema_name = FunctionNames.restricted_schema(rpc_action.name)

    case rpc_action |> EntrypointOptions.entrypoint!() |> EntrypointOptions.load_restrictions() do
      :none ->
        {nil, base_schema}

      {:deny, deny} ->
        schema_def =
          generate_deny_schema(resource, deny, schema_name, base_schema, resource_lookup)

        {schema_def, schema_name}

      {:allow, allow_only} ->
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

  defp generate_deny_schema(resource, denied_loads, schema_name, base_schema, resource_lookup) do
    {flat_denies, nested_denies} = partition_restrictions(denied_loads)

    {nested_schemas, nested_overrides} =
      process_nested_fields(:deny, resource, nested_denies, schema_name, resource_lookup)

    # A bare denied attribute is no load: only the loads under it are denied,
    # so it keeps its attributes.
    flat_overrides =
      flat_denies
      |> Enum.map(&bare_denied_attribute_override(resource, &1, resource_lookup))
      |> Enum.reject(&is_nil/1)

    schema =
      build_restricted_schema(
        schema_name,
        base_schema,
        format_fields_for_typescript(resource, flat_denies ++ override_names(nested_overrides)),
        generate_override_fields(flat_overrides ++ nested_overrides)
      )

    with_nested_schemas(nested_schemas, schema)
  end

  defp bare_denied_attribute_override(resource, field_name, resource_lookup) do
    case resolve_field_info(resource, field_name, resource_lookup) do
      {:resource, %Ash.Info.Manifest.Field{kind: :attribute}, _destination, _suffix} = info ->
        attributes_only_override(resource, info, resource_lookup)

      {:union, %Ash.Info.Manifest.Field{kind: :attribute}, _union} = info ->
        attributes_only_override(resource, info, resource_lookup)

      _load_or_not_found ->
        nil
    end
  end

  # The nested schemas the `{field, entries}` restrictions need, joined, and
  # the overrides putting them in place.
  defp process_nested_fields(mode, resource, nested, schema_name, resource_lookup) do
    {nested_schema_defs, overrides} =
      nested
      |> Enum.map(fn {field_name, entries} ->
        process_nested_field(mode, resource, field_name, entries, schema_name, resource_lookup)
      end)
      |> Enum.unzip()

    {nested_schema_defs |> List.flatten() |> Enum.reject(&(&1 == "")) |> Enum.join("\n"),
     Enum.reject(overrides, &is_nil/1)}
  end

  defp with_nested_schemas("", schema), do: schema

  defp with_nested_schemas(nested_schemas, schema) do
    """
    #{nested_schemas}
    #{schema}
    """
  end

  defp override_names(overrides), do: Enum.map(overrides, &elem(&1, 0))

  # A `{field, entries}` restriction (`mode` is `:deny` or `:allow`): the
  # field gets a nested schema restricting its destination by `entries`, and a
  # union field one per member an entry restricts.
  defp process_nested_field(mode, resource, field_name, entries, schema_name, resource_lookup) do
    generate = &generate_schema(mode, &1, &2, &3, &4, resource_lookup)

    case resolve_field_info(resource, field_name, resource_lookup) do
      {:relationship, rel} ->
        nested_schema_name = nested_schema_name(schema_name, [rel.name])
        base_schema = resource_schema(rel.destination, "ResourceSchema")

        {generate.(rel.destination, entries, nested_schema_name, base_schema),
         {rel.name, generate_relationship_override(resource, rel, nested_schema_name)}}

      {:resource, field, destination, base_suffix} ->
        nested_schema_name = nested_schema_name(schema_name, [field.name])
        base_schema = resource_schema(destination, base_suffix)

        {generate.(destination, entries, nested_schema_name, base_schema),
         {field.name, resource_field_override(resource, field, nested_schema_name)}}

      {:union, field, union} ->
        {nested_defs, member_schemas} =
          for {member, member_entries} when is_list(member_entries) <- entries,
              {:embedded, _member, member_resource} <- [LoadPaths.member_step(union, member)],
              reduce: {[], attributes_only_member_schemas(mode, union, entries, resource_lookup)} do
            {defs, schemas} ->
              member_schema_name = nested_schema_name(schema_name, [field.name, member])
              base_schema = resource_schema(member_resource, "ResourceSchema")

              nested_def =
                generate.(member_resource, member_entries, member_schema_name, base_schema)

              {[nested_def | defs], Map.put(schemas, member, member_schema_name)}
          end

        {Enum.reverse(nested_defs),
         {field.name, union_override(resource, field, union, member_schemas)}}

      :not_found ->
        {"", nil}
    end
  end

  defp generate_schema(:deny, resource, entries, schema_name, base_schema, resource_lookup),
    do: generate_deny_schema(resource, entries, schema_name, base_schema, resource_lookup)

  defp generate_schema(:allow, resource, entries, schema_name, base_schema, resource_lookup),
    do: generate_allow_only_schema(resource, entries, schema_name, base_schema, resource_lookup)

  # The members of a restricted union that keep their attributes only, unless
  # a `{member, entries}` entry restricts them: under a deny, the bare denied
  # members (a bare member is no load, so it keeps its attributes); under an
  # allow, every member.
  defp attributes_only_member_schemas(:deny, union, entries, resource_lookup),
    do:
      Map.take(attributes_only_members(union, resource_lookup), Enum.filter(entries, &is_atom/1))

  defp attributes_only_member_schemas(:allow, union, _entries, resource_lookup),
    do: attributes_only_members(union, resource_lookup)

  defp generate_allow_only_schema(
         resource,
         allowed_loads,
         schema_name,
         base_schema,
         resource_lookup
       ) do
    {flat_allows, nested_allows} = partition_restrictions(allowed_loads)
    nested_field_names = Enum.map(nested_allows, &elem(&1, 0))
    allowed_loadables = flat_allows ++ nested_field_names

    {nested_schemas, nested_overrides} =
      process_nested_fields(:allow, resource, nested_allows, schema_name, resource_lookup)

    # Flat allows use AttributesOnlySchema (no nested loads allowed)
    flat_overrides =
      flat_allows
      |> Enum.map(&process_flat_allow_field(resource, &1, resource_lookup))
      |> Enum.reject(&is_nil/1)

    unnamed_overrides = unnamed_attribute_overrides(resource, allowed_loadables, resource_lookup)

    # A flat allow is omitted only when an override replaces it (relationships,
    # embedded resources and unions get an AttributesOnlySchema override so their
    # own loads stay out of reach). Scalar loads - calculations and aggregates -
    # have no override, so omitting them would forbid the very field the action
    # allows.
    fields_to_omit =
      (get_loadable_field_names(resource, resource_lookup) -- allowed_loadables) ++
        nested_field_names ++ override_names(flat_overrides) ++ override_names(unnamed_overrides)

    schema =
      build_restricted_schema(
        schema_name,
        base_schema,
        format_fields_for_typescript(resource, fields_to_omit),
        generate_override_fields(nested_overrides ++ flat_overrides ++ unnamed_overrides)
      )

    with_nested_schemas(nested_schemas, schema)
  end

  defp process_flat_allow_field(resource, field_name, resource_lookup) do
    case resolve_field_info(resource, field_name, resource_lookup) do
      {:relationship, rel} ->
        {rel.name,
         generate_relationship_override(
           resource,
           rel,
           attributes_only_type(rel.destination, resource_lookup)
         )}

      info ->
        attributes_only_override(resource, info, resource_lookup)
    end
  end

  # Under allowed_loads, the loads under an attribute the entries don't name
  # are not allowed: an embedded attribute keeps its attributes only, and so
  # does each resource member of a union attribute.
  defp unnamed_attribute_overrides(resource, named_fields, resource_lookup),
    do:
      attributes_only_overrides(
        resource,
        "ResourceSchema",
        named_fields,
        resource_lookup,
        %{}
      )

  # A field holding a resource, or a union, retyped with its attributes only
  # (a union: each resource member's); nil for any other field.
  defp attributes_only_override(resource, {:resource, field, destination, _suffix}, lookup),
    do:
      {field.name,
       resource_field_override(resource, field, attributes_only_type(destination, lookup))}

  defp attributes_only_override(resource, {:union, field, union}, lookup),
    do:
      {field.name, union_override(resource, field, union, attributes_only_members(union, lookup))}

  defp attributes_only_override(_resource, _load_or_not_found, _lookup), do: nil

  # The type of `resource` with its attributes only, for a place where no load
  # under it is allowed. Its AttributesOnlySchema types the resource members of
  # its union attributes in full (an aggregate holding it accepts their loads),
  # so where it has such a union, directly or through an embedded attribute,
  # those attributes are replaced with their attributes only. A resource
  # already on the way (the keys of `seen`, a plain map: dialyzer flags a
  # `MapSet` threaded through this recursion as opaque) keeps its
  # AttributesOnlySchema.
  defp attributes_only_type(resource, resource_lookup, seen \\ %{}) do
    base = resource_schema(resource, "AttributesOnlySchema")

    overrides =
      if Map.has_key?(seen, resource),
        do: [],
        else:
          attributes_only_overrides(
            resource,
            "AttributesOnlySchema",
            [],
            resource_lookup,
            Map.put(seen, resource, true)
          )

    case overrides do
      [] ->
        base

      overrides ->
        omits = format_fields_for_typescript(resource, override_names(overrides))
        fields = Enum.map_join(overrides, " ", fn {_name, override} -> override <> ";" end)
        "(Omit<#{base}, #{omits}> & { #{fields} })"
    end
  end

  # The attributes of `resource` (but `skip`) whose type in its `suffix`
  # schema still allows loads under them, retyped with their attributes only:
  # an embedded attribute typed otherwise than with its attributes-only type,
  # and a union attribute with resource members.
  defp attributes_only_overrides(resource, suffix, skip, resource_lookup, seen) do
    resource_lookup
    |> Ash.Info.Manifest.get_resource!(resource)
    |> Ash.Info.Manifest.Resource.fields_by_kind(:attribute)
    |> Enum.reject(&(&1.name in skip))
    |> Enum.flat_map(fn attribute ->
      case resolve_field_info(resource, attribute.name, resource_lookup) do
        {:resource, field, destination, _suffix} ->
          type = attributes_only_type(destination, resource_lookup, seen)

          if type == resource_schema(destination, suffix),
            do: [],
            else: [{field.name, resource_field_override(resource, field, type)}]

        {:union, field, union} ->
          case attributes_only_members(union, resource_lookup, seen) do
            members when map_size(members) == 0 -> []
            members -> [{field.name, union_override(resource, field, union, members)}]
          end

        _other ->
          []
      end
    end)
  end

  # The step `LoadPaths` takes through `field_name`, the same walk VerifyRpc
  # checks restrictions with. A relationship to an unexposed resource has no
  # key in the base schema. A field holding a resource (an embedded attribute
  # or aggregate, or a calculation returning a resource) carries the suffix of
  # the schema the base schema renders it with: an aggregate's attributes only.
  defp resolve_field_info(resource, field_name, resource_lookup) do
    case LoadPaths.step(resource_lookup, AshTypescript.type_lookup(), resource, field_name) do
      {:relationship, rel, _destination} ->
        if Helpers.exposed_relationship?(rel, resource_lookup),
          do: {:relationship, rel},
          else: :not_found

      {kind, field, destination} when kind in [:embedded, :resource_calculation] ->
        suffix = if field.kind == :aggregate, do: "AttributesOnlySchema", else: "ResourceSchema"
        {:resource, field, destination, suffix}

      {:union, field, union} ->
        {:union, field, union}

      {:leaf, _field} ->
        :not_found

      :invalid ->
        :not_found
    end
  end

  defp resource_schema(resource, suffix), do: Helpers.build_resource_type_name(resource) <> suffix

  # A nested schema's type name: the schema's name, then each raw name made
  # an identifier first (`:best_children?` → `BestChildren`), so a raw name
  # with a `?` or other non-identifier characters gives a valid type name.
  defp nested_schema_name(schema_name, raw_names),
    do:
      schema_name <>
        Enum.map_join(raw_names, &snake_to_pascal_case(NameValidation.suggest_name(&1)))

  # A field holding a resource, with `schema` in place of the resource's
  # schema, in the shape the base schema gives it: a calculation with
  # arguments keeps them.
  defp resource_field_override(resource, field, schema) do
    type =
      if ResourceSchemas.classify_field(field) == :calculation,
        do: ResourceSchemas.calculation_field_type(resource, field, array_of(field, schema)),
        else: ResourceSchemas.embedded_field_type(field, schema)

    "#{ClientNames.resource_field(resource, field.name)}: #{type}"
  end

  # A union field with `member_schemas` (`TypeMapper.build_union_type_from_members/2`),
  # in the shape the base schema gives it.
  defp union_override(resource, field, union, member_schemas) do
    union_type = TypeMapper.build_union_type_from_members(union, member_schemas)

    type =
      if ResourceSchemas.classify_field(field) == :calculation,
        do: ResourceSchemas.calculation_field_type(resource, field, array_of(field, union_type)),
        else: ResourceSchemas.typed_field_type(field, union_type)

    "#{ClientNames.resource_field(resource, field.name)}: #{type}"
  end

  # Each member holding a resource, mapped to its attributes-only type.
  defp attributes_only_members(union, resource_lookup, seen \\ %{}) do
    for %{name: member} <- union.members || [],
        {:embedded, _member, member_resource} <- [LoadPaths.member_step(union, member)],
        into: %{},
        do: {member, attributes_only_type(member_resource, resource_lookup, seen)}
  end

  defp array_of(%Ash.Info.Manifest.Field{type: %Ash.Info.Manifest.Type{kind: :array}}, type),
    do: "Array<#{type}>"

  defp array_of(%Ash.Info.Manifest.Field{}, type), do: type

  # A relationship with `schema` in place of its destination's schema, query
  # markers included.
  defp generate_relationship_override(resource, rel, schema),
    do:
      "#{ClientNames.resource_field(resource, rel.name)}: " <>
        ResourceSchemas.relationship_field_type(rel, schema)

  defp generate_override_fields(overrides) do
    Enum.map_join(overrides, "\n", fn {_field_name, override_str} -> "  #{override_str};" end)
  end

  defp partition_restrictions(restrictions), do: Enum.split_with(restrictions, &is_atom/1)

  defp get_loadable_field_names(resource, resource_lookup) do
    api_resource = Ash.Info.Manifest.get_resource!(resource_lookup, resource)

    relationships =
      api_resource
      |> Ash.Info.Manifest.Resource.all_relationships()
      |> Enum.filter(&Helpers.exposed_relationship?(&1, resource_lookup))
      |> Enum.map(& &1.name)

    calculations =
      api_resource
      |> Ash.Info.Manifest.Resource.fields_by_kind(:calculation)
      |> Enum.map(& &1.name)

    aggregates =
      api_resource
      |> Ash.Info.Manifest.Resource.fields_by_kind(:aggregate)
      |> Enum.map(& &1.name)

    relationships ++ calculations ++ aggregates
  end

  # Emits one restricted schema.
  #
  # `Omit` alone cannot restrict scalar loads: field selection reads leaf names
  # from `__primitiveFields` (`LeafFieldSelection<T> = T["__primitiveFields"]`),
  # a string-literal union that `Omit` does not touch. Calculations and
  # aggregates therefore stayed selectable no matter what was omitted, so every
  # restricted schema rewrites that union with the same key list.
  defp build_restricted_schema(schema_name, base_schema, formatted_omits, override_fields) do
    body =
      [
        ~s(  __primitiveFields: Exclude<#{base_schema}["__primitiveFields"], #{formatted_omits}>;),
        override_fields
      ]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join("\n")

    """
    type #{schema_name} = Omit<#{base_schema}, '__primitiveFields' | #{formatted_omits}> & {
    #{body}
    };
    """
  end

  defp format_fields_for_typescript(_resource, fields) when fields == [], do: "never"

  # Omit keys must match the resource schema's own keys, the decorated client
  # names - a `field_names is_active?: "isActive"` mapping would otherwise emit
  # 'isActive?' and the Omit would silently do nothing.
  defp format_fields_for_typescript(resource, fields) do
    Enum.map_join(fields, " | ", &"'#{ClientNames.resource_field(resource, &1)}'")
  end
end
