# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.FieldProcessing.FieldSelector do
  @moduledoc """
  Unified field selection processor using type-driven recursive dispatch.

  This module mirrors the architecture of `ValueFormatter`, using the same
  `{type, constraints}` pattern for type-driven dispatch. Each type is
  self-describing - no separate classification step is needed.

  ## Design Principle

  The key insight is that field selection and value formatting are parallel
  operations - both traverse composite types recursively based on type information.
  By using the same dispatch pattern, we achieve consistency and simplicity.

  ## Type Categories

  | Category | Detection | Handler |
  |----------|-----------|---------|
  | Ash Resource | `Ash.Resource.Info.resource?(type)` | `select_resource_fields/3` |
  | TypedStruct/NewType/CustomType | `typescript_field_names/0` callback | `select_typed_struct_fields/3` |
  | Typed Map/Struct | Has `fields` constraints | `select_typed_map_fields/3` |
  | Tuple | `Ash.Type.Tuple` | `select_tuple_fields/3` |
  | Union | `Ash.Type.Union` | `select_union_fields/3` |
  | Array | `{:array, inner_type}` | Recurse with inner type |
  | Primitive | Default | Validate no fields requested |
  """

  alias AshTypescript.FieldFormatter
  alias AshTypescript.Resource.Info, as: ResourceInfo
  alias AshTypescript.Rpc.FieldProcessing.FieldSelector.Validation
  alias AshTypescript.TypeSystem.Introspection

  @type select_result :: {select :: [atom()], load :: [term()], template :: [term()]}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Processes requested fields for a given resource and action.

  Returns `{:ok, {select_fields, load_fields, extraction_template}}` or `{:error, error}`.

  ## Parameters

  - `resource` - The Ash resource module
  - `action_name` - The action name (atom)
  - `requested_fields` - List of field selections (atoms, strings, or maps)

  ## Examples

      iex> process(MyApp.Todo, :read, [:id, :title, %{user: [:id, :name]}])
      {:ok, {[:id, :title], [{:user, [:id, :name]}], [:id, :title, {:user, [:id, :name]}]}}
  """
  @spec process(module(), atom(), list()) :: {:ok, select_result()} | {:error, term()}
  def process(resource, action_name, requested_fields) do
    action = Ash.Resource.Info.action(resource, action_name)

    if is_nil(action) do
      throw({:action_not_found, action_name})
    end

    {type, constraints} = action_to_type_spec(resource, action)
    {select, load, template} = select_fields(type, constraints, requested_fields, [])
    formatted_template = format_extraction_template(template)

    {:ok, {select, load, formatted_template}}
  catch
    error_tuple -> {:error, error_tuple}
  end

  @doc """
  Converts an action to its type specification.

  Returns `{type, constraints}` tuple representing the action's return type.
  """
  @spec action_to_type_spec(module(), Ash.Resource.Actions.action()) ::
          {atom() | tuple(), keyword()}
  def action_to_type_spec(resource, action) do
    case action.type do
      type when type in [:create, :update, :destroy] ->
        {resource, []}

      :read ->
        if action.get? do
          {resource, []}
        else
          {{:array, resource}, []}
        end

      :action ->
        case action.returns do
          nil -> {:any, []}
          type -> {type, action.constraints || []}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Core Type-Driven Dispatch
  # ---------------------------------------------------------------------------

  @doc """
  Main recursive dispatch function for field selection.

  Mirrors `ValueFormatter.format/5` - uses the same type detection and dispatch pattern.
  Each type category has its own handler that may recurse back into this function.
  """
  @spec select_fields(atom() | tuple(), keyword(), list(), list()) :: select_result()
  def select_fields(type, constraints, requested_fields, path) do
    {unwrapped_type, full_constraints} = Introspection.unwrap_new_type(type, constraints)

    cond do
      match?({:array, _}, type) ->
        {:array, inner_type} = type
        inner_constraints = Keyword.get(constraints, :items, [])
        select_fields(inner_type, inner_constraints, requested_fields, path)

      is_atom(unwrapped_type) && Ash.Resource.Info.resource?(unwrapped_type) ->
        select_resource_fields(unwrapped_type, requested_fields, path)

      unwrapped_type == Ash.Type.Struct &&
          Introspection.is_resource_instance_of?(full_constraints) ->
        resource = Keyword.get(full_constraints, :instance_of)
        select_resource_fields(resource, requested_fields, path)

      Introspection.has_typescript_field_names?(full_constraints[:instance_of]) ->
        select_typed_struct_fields(full_constraints, requested_fields, path)

      unwrapped_type == Ash.Type.Map && Introspection.has_field_constraints?(full_constraints) ->
        select_typed_map_fields(full_constraints, requested_fields, path, "map")

      unwrapped_type == Ash.Type.Struct && Introspection.has_field_constraints?(full_constraints) ->
        select_typed_map_fields(full_constraints, requested_fields, path)

      unwrapped_type == Ash.Type.Keyword && Introspection.has_field_constraints?(full_constraints) ->
        select_typed_map_fields(full_constraints, requested_fields, path)

      unwrapped_type == Ash.Type.Tuple ->
        select_tuple_fields(full_constraints, requested_fields, path)

      unwrapped_type == Ash.Type.Union ->
        select_union_fields(full_constraints, requested_fields, path, "union_attribute")

      type == :any ->
        select_generic_fields(requested_fields, path)

      true ->
        if requested_fields != [] do
          throw({:invalid_field_selection, :primitive_type, type, requested_fields, path})
        end

        {[], [], []}
    end
  end

  # ---------------------------------------------------------------------------
  # Resource Field Selection
  # ---------------------------------------------------------------------------

  @doc """
  Selects fields from an Ash resource.

  Handles attributes, calculations, relationships, and aggregates.
  """
  def select_resource_fields(resource, requested_fields, path) do
    Validation.check_for_duplicates(requested_fields, path)

    Enum.reduce(requested_fields, {[], [], []}, fn field, acc ->
      field = atomize_field_name(field, resource)

      case parse_field_request(field) do
        {:simple, field_name} ->
          process_simple_resource_field(resource, field_name, path, acc)

        {:nested, field_name, nested_fields} ->
          process_nested_resource_field(resource, field_name, nested_fields, path, acc)

        {:with_args, calc_name, args, fields} ->
          process_calculation_with_args(resource, calc_name, args, fields, path, acc)

        {:multi_nested, entries} ->
          # Handle multi-key maps by processing each entry
          # Each entry could be a regular nested field or a calculation with args
          Enum.reduce(entries, acc, fn {field_name, nested_fields}, inner_acc ->
            cond do
              # If nested_fields is a list, it's regular nested selection
              is_list(nested_fields) ->
                process_nested_resource_field(
                  resource,
                  field_name,
                  nested_fields,
                  path,
                  inner_acc
                )

              # If nested_fields is a map, check if it's a calculation with args
              is_map(nested_fields) ->
                case get_args_and_fields(nested_fields) do
                  {:ok, args, fields} ->
                    process_calculation_with_args(
                      resource,
                      field_name,
                      args,
                      fields,
                      path,
                      inner_acc
                    )

                  :not_args_structure ->
                    process_nested_resource_field(
                      resource,
                      field_name,
                      nested_fields,
                      path,
                      inner_acc
                    )
                end

              true ->
                process_nested_resource_field(
                  resource,
                  field_name,
                  nested_fields,
                  path,
                  inner_acc
                )
            end
          end)
      end
    end)
  end

  defp process_simple_resource_field(resource, field_name, path, {select, load, template}) do
    internal_name = resolve_resource_field_name(resource, field_name)
    {field_type, constraints, category} = get_resource_field_info(resource, internal_name, path)

    if category == :calculation_with_args do
      throw({:calculation_requires_args, internal_name, path})
    end

    if requires_nested_selection?(field_type, constraints) do
      throw({:requires_field_selection, category, internal_name, path})
    end

    case category do
      :attribute ->
        {select ++ [internal_name], load, template ++ [internal_name]}

      :relationship ->
        throw({:requires_field_selection, :relationship, internal_name, path})

      cat when cat in [:calculation, :aggregate] ->
        {select, load ++ [internal_name], template ++ [internal_name]}
    end
  end

  defp process_nested_resource_field(
         resource,
         field_name,
         nested_fields,
         path,
         {select, load, template}
       ) do
    internal_name = resolve_resource_field_name(resource, field_name)

    {field_type, field_constraints, category} =
      get_resource_field_info(resource, internal_name, path)

    if category == :calculation_with_args do
      throw({:invalid_calculation_args, internal_name, path})
    end

    if category == :aggregate do
      throw({:invalid_field_selection, internal_name, :aggregate, path})
    end

    if category == :calculation && is_map(nested_fields) do
      throw({:invalid_calculation_args, internal_name, path})
    end

    if category == :calculation && !requires_nested_selection?(field_type, field_constraints) do
      throw({:field_does_not_support_nesting, internal_name, path})
    end

    if category == :attribute && !requires_nested_selection?(field_type, field_constraints) do
      throw({:field_does_not_support_nesting, internal_name, path})
    end

    # For union attributes, nested_fields can be a map (member selection)
    if category == :union_attribute do
      if is_list(nested_fields) && nested_fields == [] do
        throw({:requires_field_selection, :union, internal_name, path})
      end
    else
      Validation.validate_non_empty(nested_fields, internal_name, path, category)
    end

    new_path = path ++ [internal_name]

    {nested_select, nested_load, nested_template} =
      select_fields(field_type, field_constraints, nested_fields, new_path)

    case category do
      cat
      when cat in [
             :attribute,
             :embedded_resource,
             :tuple,
             :field_constrained_type,
             :union_attribute
           ] ->
        new_load =
          if nested_load != [] do
            load ++ [{internal_name, nested_load}]
          else
            load
          end

        {select ++ [internal_name], new_load, template ++ [{internal_name, nested_template}]}

      :relationship ->
        rel = Ash.Resource.Info.relationship(resource, internal_name)
        dest_resource = rel && rel.destination

        unless dest_resource && ResourceInfo.typescript_resource?(dest_resource) do
          throw({:unknown_field, internal_name, resource, path})
        end

        load_spec = build_load_spec(internal_name, nested_select, nested_load)
        {select, load ++ [load_spec], template ++ [{internal_name, nested_template}]}

      cat when cat in [:calculation, :calculation_complex] ->
        load_spec = build_load_spec(internal_name, nested_select, nested_load)
        {select, load ++ [load_spec], template ++ [{internal_name, nested_template}]}

      :aggregate ->
        load_spec = build_load_spec(internal_name, nested_select, nested_load)
        {select, load ++ [load_spec], template ++ [{internal_name, nested_template}]}

      :calculation_with_args ->
        throw({:invalid_calculation_args, internal_name, path})
    end
  end

  defp process_calculation_with_args(
         resource,
         calc_name,
         args,
         fields,
         path,
         {select, load, template}
       ) do
    internal_name = resolve_resource_field_name(resource, calc_name)
    calc = Ash.Resource.Info.calculation(resource, internal_name)

    if is_nil(calc) do
      throw({:unknown_field, internal_name, resource, path})
    end

    {field_type, field_constraints} = {calc.type, calc.constraints || []}
    new_path = path ++ [internal_name]
    is_complex_return_type = requires_nested_selection?(field_type, field_constraints)

    calc_accepts_args = has_any_arguments?(calc)
    calc_requires_args = has_required_arguments?(calc)
    has_non_empty_args = args != nil && args != %{}

    cond do
      calc_accepts_args && args == nil ->
        throw({:invalid_calculation_args, internal_name, path})

      has_non_empty_args && !calc_accepts_args ->
        throw({:invalid_calculation_args, internal_name, path})

      !calc_accepts_args && !is_complex_return_type && args != nil ->
        throw({:invalid_calculation_args, internal_name, path})

      calc_requires_args && !has_non_empty_args ->
        throw({:invalid_calculation_args, internal_name, path})

      true ->
        :ok
    end

    {nested_select, nested_load, nested_template} =
      cond do
        not is_nil(fields) and not is_complex_return_type ->
          throw({:invalid_field_selection, internal_name, :calculation, path})

        is_list(fields) and fields != [] ->
          select_fields(field_type, field_constraints, fields, new_path)

        is_complex_return_type ->
          throw({:requires_field_selection, :complex_type, internal_name, path})

        true ->
          {[], [], []}
      end

    load_fields =
      case nested_load do
        [] -> nested_select
        _ -> nested_select ++ nested_load
      end

    load_spec =
      cond do
        args != nil && load_fields != [] ->
          {internal_name, {args, load_fields}}

        args != nil ->
          {internal_name, args}

        load_fields != [] ->
          {internal_name, load_fields}

        true ->
          internal_name
      end

    template_item =
      if nested_template == [] do
        internal_name
      else
        {internal_name, nested_template}
      end

    {select, load ++ [load_spec], template ++ [template_item]}
  end

  defp get_resource_field_info(resource, field_name, path) do
    cond do
      attr = Ash.Resource.Info.public_attribute(resource, field_name) ->
        constraints = attr.constraints || []
        category = classify_attribute_category(attr.type, constraints)
        {attr.type, constraints, category}

      rel = Ash.Resource.Info.public_relationship(resource, field_name) ->
        type = if rel.cardinality == :many, do: {:array, rel.destination}, else: rel.destination
        {type, [], :relationship}

      calc = Ash.Resource.Info.public_calculation(resource, field_name) ->
        constraints = calc.constraints || []

        category =
          cond do
            has_any_arguments?(calc) -> :calculation_with_args
            requires_nested_selection?(calc.type, constraints) -> :calculation_complex
            true -> :calculation
          end

        {calc.type, constraints, category}

      agg = Ash.Resource.Info.public_aggregate(resource, field_name) ->
        {agg.type, agg.constraints || [], :aggregate}

      true ->
        throw({:unknown_field, field_name, resource, path})
    end
  end

  defp classify_attribute_category(type, constraints) do
    {unwrapped_type, unwrapped_constraints} =
      case type do
        {:array, inner} ->
          Introspection.unwrap_new_type(inner, Keyword.get(constraints, :items, []))

        t when is_atom(t) ->
          Introspection.unwrap_new_type(t, constraints)

        _ ->
          {type, constraints}
      end

    cond do
      # Embedded resources
      is_atom(unwrapped_type) && Introspection.is_embedded_resource?(unwrapped_type) ->
        :embedded_resource

      # Tuple types with fields
      unwrapped_type == Ash.Type.Tuple &&
          Keyword.has_key?(unwrapped_constraints, :fields) ->
        :tuple

      # Keyword types with fields
      unwrapped_type == Ash.Type.Keyword &&
          Keyword.has_key?(unwrapped_constraints, :fields) ->
        :field_constrained_type

      # Union types
      unwrapped_type == Ash.Type.Union ->
        :union_attribute

      # Other types with field constraints
      Keyword.has_key?(unwrapped_constraints, :fields) &&
          Keyword.get(unwrapped_constraints, :fields) != [] ->
        :field_constrained_type

      # Simple attribute
      true ->
        :attribute
    end
  end

  defp has_any_arguments?(calc) do
    case calc.arguments do
      [] -> false
      nil -> false
      args when is_list(args) -> length(args) > 0
    end
  end

  defp has_required_arguments?(calc) do
    case calc.arguments do
      [] ->
        false

      nil ->
        false

      args when is_list(args) ->
        Enum.any?(args, fn arg -> !arg.allow_nil? end)
    end
  end

  # ---------------------------------------------------------------------------
  # TypedStruct Field Selection
  # ---------------------------------------------------------------------------

  @doc """
  Selects fields from a TypedStruct or NewType with typescript_field_names callback.
  """
  def select_typed_struct_fields(constraints, requested_fields, path) do
    if requested_fields == [] do
      throw({:requires_field_selection, :field_constrained_type, nil})
    end

    field_specs = get_field_specs(constraints)
    instance_of = Keyword.get(constraints, :instance_of)
    ts_field_names = Introspection.get_typescript_field_names_map(instance_of)
    reverse_map = Introspection.build_reverse_field_names_map(ts_field_names)

    Validation.check_for_duplicates(requested_fields, path)

    Enum.reduce(requested_fields, {[], [], []}, fn field, {select, load, template} ->
      case parse_field_request(field) do
        {:simple, field_name} ->
          internal_name = resolve_typed_struct_field(field_name, reverse_map)
          Validation.validate_field_exists!(internal_name, field_specs, path)
          {select, load, template ++ [internal_name]}

        {:nested, field_name, nested_fields} ->
          internal_name = resolve_typed_struct_field(field_name, reverse_map)
          Validation.validate_field_exists!(internal_name, field_specs, path)

          field_spec = Keyword.get(field_specs, internal_name)
          field_type = Keyword.get(field_spec, :type)
          field_constraints = Keyword.get(field_spec, :constraints, [])
          new_path = path ++ [internal_name]

          {_nested_select, _nested_load, nested_template} =
            select_fields(field_type, field_constraints, nested_fields, new_path)

          {select, load, template ++ [{internal_name, nested_template}]}

        {:with_args, _calc_name, _args, _fields} ->
          throw({:invalid_field_format, field, path})
      end
    end)
  end

  defp resolve_typed_struct_field(field_name, reverse_map) when is_binary(field_name) do
    case Map.get(reverse_map, field_name) do
      nil ->
        formatter = AshTypescript.Rpc.input_field_formatter()
        converted = FieldFormatter.parse_input_field(field_name, formatter)
        if is_atom(converted), do: converted, else: String.to_atom(converted)

      internal ->
        internal
    end
  end

  defp resolve_typed_struct_field(field_name, _reverse_map) when is_atom(field_name),
    do: field_name

  # ---------------------------------------------------------------------------
  # Typed Map Field Selection
  # ---------------------------------------------------------------------------

  @doc """
  Selects fields from a typed map (Ash.Type.Map/Keyword with field constraints).

  The error_type parameter allows distinguishing between different type categories
  for better error messages.
  """
  def select_typed_map_fields(
        constraints,
        requested_fields,
        path,
        error_type \\ "field_constrained_type"
      ) do
    field_specs = get_field_specs(constraints)

    if field_specs == [] do
      {[], [], []}
    else
      if requested_fields == [] do
        throw({:requires_field_selection, :field_constrained_type, nil})
      end

      Validation.check_for_duplicates(requested_fields, path)

      Enum.reduce(requested_fields, {[], [], []}, fn field, {select, load, template} ->
        case parse_field_request(field) do
          {:simple, field_name} ->
            internal_name = convert_to_field_atom(field_name)

            unless Keyword.has_key?(field_specs, internal_name) do
              throw({:unknown_field, field_name, error_type, path})
            end

            {select, load, template ++ [internal_name]}

          {:nested, field_name, nested_fields} ->
            internal_name = convert_to_field_atom(field_name)

            unless Keyword.has_key?(field_specs, internal_name) do
              throw({:unknown_field, field_name, error_type, path})
            end

            field_spec = Keyword.get(field_specs, internal_name)
            field_type = Keyword.get(field_spec, :type)
            field_constraints = Keyword.get(field_spec, :constraints, [])
            new_path = path ++ [internal_name]

            {_nested_select, _nested_load, nested_template} =
              select_fields(field_type, field_constraints, nested_fields, new_path)

            {select, load, template ++ [{internal_name, nested_template}]}

          {:with_args, _calc_name, _args, _fields} ->
            throw({:invalid_field_format, field, path})

          {:multi_nested, entries} ->
            Enum.reduce(entries, {select, load, template}, fn {field_name, nested}, {s, l, t} ->
              internal_name = convert_to_field_atom(field_name)
              Validation.validate_field_exists!(internal_name, field_specs, path, error_type)

              field_spec = Keyword.get(field_specs, internal_name)
              field_type = Keyword.get(field_spec, :type)
              field_constraints = Keyword.get(field_spec, :constraints, [])
              new_path = path ++ [internal_name]

              {_nested_select, _nested_load, nested_template} =
                select_fields(field_type, field_constraints, nested, new_path)

              {s, l, t ++ [{internal_name, nested_template}]}
            end)
        end
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Tuple Field Selection
  # ---------------------------------------------------------------------------

  @doc """
  Selects fields from a tuple type using named fields.

  Tuples in Ash have named positions (like :latitude, :longitude) and the
  template stores both the field_name and its index for result processing.
  When no fields are requested, all fields are returned.
  """
  def select_tuple_fields(constraints, requested_fields, path) do
    field_specs = Keyword.get(constraints, :fields, [])
    field_names = Enum.map(field_specs, &elem(&1, 0))

    # If no fields requested, return all fields
    if requested_fields == [] do
      template =
        field_names
        |> Enum.with_index()
        |> Enum.map(fn {name, index} -> %{field_name: name, index: index} end)

      {[], [], template}
    else
      Validation.check_for_duplicates(requested_fields, path)

      Enum.reduce(requested_fields, {[], [], []}, fn field, {select, load, template} ->
        case parse_field_request(field) do
          {:simple, field_name} ->
            field_atom = convert_to_field_atom(field_name)

            if Keyword.has_key?(field_specs, field_atom) do
              index = Enum.find_index(field_names, &(&1 == field_atom))
              {select, load, template ++ [%{field_name: field_atom, index: index}]}
            else
              throw({:unknown_field, field_atom, "tuple", path})
            end

          {:nested, field_name, nested_fields} ->
            field_atom = convert_to_field_atom(field_name)

            if Keyword.has_key?(field_specs, field_atom) do
              field_spec = Keyword.get(field_specs, field_atom)
              field_type = Keyword.get(field_spec, :type)
              field_constraints = Keyword.get(field_spec, :constraints, [])
              new_path = path ++ [field_atom]

              {_nested_select, _nested_load, nested_template} =
                select_fields(field_type, field_constraints, nested_fields, new_path)

              {select, load, template ++ [{field_name, nested_template}]}
            else
              throw({:unknown_field, field_atom, "tuple", path})
            end

          {:multi_nested, entries} ->
            Enum.reduce(entries, {select, load, template}, fn {field_name, nested_fields},
                                                              {s, l, t} ->
              field_atom = convert_to_field_atom(field_name)

              unless Keyword.has_key?(field_specs, field_atom) do
                throw({:unknown_field, field_atom, "tuple", path})
              end

              index = Enum.find_index(field_names, &(&1 == field_atom))

              if is_list(nested_fields) do
                field_spec = Keyword.get(field_specs, field_atom)
                field_type = Keyword.get(field_spec, :type)
                field_constraints = Keyword.get(field_spec, :constraints, [])
                new_path = path ++ [field_atom]

                {_nested_select, _nested_load, nested_template} =
                  select_fields(field_type, field_constraints, nested_fields, new_path)

                {s, l, t ++ [{field_atom, nested_template}]}
              else
                {s, l, t ++ [%{field_name: field_atom, index: index}]}
              end
            end)

          {:with_args, _calc_name, _args, _fields} ->
            throw({:invalid_field_format, field, path})
        end
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Union Field Selection
  # ---------------------------------------------------------------------------

  @doc """
  Selects fields from a union type.

  Supports:
  - Simple member selection: [:member_name]
  - Member with nested fields: [%{member_name: fields}]
  - Multiple members in a single map: %{member1: fields1, member2: fields2}
  """
  def select_union_fields(constraints, requested_fields, path, error_type \\ "union_type") do
    union_types = Keyword.get(constraints, :types, [])
    normalized_fields = normalize_union_fields(requested_fields)

    Validation.validate_non_empty(normalized_fields, "union", path, :union)
    Validation.check_for_duplicates(normalized_fields, path)

    {load_items, template_items} =
      Enum.reduce(normalized_fields, {[], []}, fn field, {load_acc, template_acc} ->
        case parse_field_request(field) do
          {:simple, member_name} ->
            process_simple_union_member(
              member_name,
              union_types,
              path,
              error_type,
              load_acc,
              template_acc
            )

          {:nested, member_name, nested_fields} ->
            process_nested_union_member(
              member_name,
              nested_fields,
              union_types,
              path,
              error_type,
              load_acc,
              template_acc
            )

          {:multi_nested, entries} ->
            Enum.reduce(entries, {load_acc, template_acc}, fn {member_name, nested_fields},
                                                              {l_acc, t_acc} ->
              process_nested_union_member(
                member_name,
                nested_fields,
                union_types,
                path,
                error_type,
                l_acc,
                t_acc
              )
            end)

          {:with_args, _calc_name, _args, _fields} ->
            throw({:invalid_field_format, field, path})
        end
      end)

    {[], load_items, template_items}
  end

  defp process_simple_union_member(
         member_name,
         union_types,
         path,
         error_type,
         load_acc,
         template_acc
       ) do
    internal_name = convert_union_member_name(member_name)

    unless Keyword.has_key?(union_types, internal_name) do
      throw({:unknown_field, internal_name, error_type, path})
    end

    member_config = Keyword.get(union_types, internal_name)
    member_type = Keyword.get(member_config, :type)
    member_constraints = Keyword.get(member_config, :constraints, [])

    # Check if member requires nested selection (embedded resources, typed maps, etc.)
    if union_member_requires_selection?(member_type, member_constraints) do
      throw({:requires_field_selection, :complex_type, internal_name, path})
    end

    {load_acc, template_acc ++ [internal_name]}
  end

  defp union_member_requires_selection?(member_type, member_constraints) do
    cond do
      is_atom(member_type) && Introspection.is_embedded_resource?(member_type) ->
        true

      Keyword.has_key?(member_constraints, :fields) &&
          Keyword.get(member_constraints, :fields) != [] ->
        true

      true ->
        requires_nested_selection?(member_type, member_constraints)
    end
  end

  defp process_nested_union_member(
         member_name,
         nested_fields,
         union_types,
         path,
         error_type,
         load_acc,
         template_acc
       ) do
    internal_name = convert_union_member_name(member_name)

    unless Keyword.has_key?(union_types, internal_name) do
      throw({:unknown_field, internal_name, error_type, path})
    end

    member_config = Keyword.get(union_types, internal_name)
    member_type = Keyword.get(member_config, :type)
    member_constraints = Keyword.get(member_config, :constraints, [])
    member_return_type = union_member_to_type_spec(member_type, member_constraints)
    new_path = path ++ [internal_name]

    {_nested_select, nested_load, nested_template} =
      select_fields(
        elem(member_return_type, 0),
        elem(member_return_type, 1),
        nested_fields,
        new_path
      )

    if nested_load != [] do
      {load_acc ++ [{internal_name, nested_load}],
       template_acc ++ [{member_name, nested_template}]}
    else
      {load_acc, template_acc ++ [{member_name, nested_template}]}
    end
  end

  defp normalize_union_fields(%{} = map) when map_size(map) > 0, do: [map]
  defp normalize_union_fields(fields) when is_list(fields), do: fields
  defp normalize_union_fields(fields), do: fields

  defp convert_union_member_name(name) when is_atom(name), do: name

  defp convert_union_member_name(name) when is_binary(name) do
    formatter = AshTypescript.Rpc.input_field_formatter()
    FieldFormatter.parse_input_field(name, formatter)
  end

  defp union_member_to_type_spec(member_type, member_constraints) do
    case member_type do
      type when is_atom(type) and type != :map ->
        if Introspection.is_embedded_resource?(type) do
          {type, []}
        else
          {type, member_constraints}
        end

      :map ->
        {Ash.Type.Map, member_constraints}

      _ ->
        {member_type, member_constraints}
    end
  end

  # ---------------------------------------------------------------------------
  # Generic Field Selection (for :any return type)
  # ---------------------------------------------------------------------------

  defp select_generic_fields(requested_fields, _path) do
    template =
      Enum.map(requested_fields, fn
        field_name when is_atom(field_name) -> field_name
        %{} = field_map -> Enum.map(field_map, fn {k, v} -> {k, v} end)
      end)

    {[], [], List.flatten(template)}
  end

  # ---------------------------------------------------------------------------
  # Helper Functions
  # ---------------------------------------------------------------------------

  defp parse_field_request(field) do
    case field do
      field_name when is_atom(field_name) or is_binary(field_name) ->
        {:simple, field_name}

      {field_name, %{} = nested} when is_map(nested) ->
        case get_args_and_fields(nested) do
          {:ok, args, fields} ->
            {:with_args, field_name, args, fields}

          :not_args_structure ->
            {:nested, field_name, nested}
        end

      {field_name, nested_fields} when is_list(nested_fields) ->
        {:nested, field_name, nested_fields}

      %{} = field_map when map_size(field_map) == 1 ->
        [{field_name, nested_fields}] = Map.to_list(field_map)

        case nested_fields do
          %{} = nested when is_map(nested) ->
            case get_args_and_fields(nested) do
              {:ok, args, fields} ->
                {:with_args, field_name, args, fields}

              :not_args_structure ->
                {:nested, field_name, nested}
            end

          nested_fields when is_list(nested_fields) ->
            {:nested, field_name, nested_fields}

          _ ->
            {:nested, field_name, nested_fields}
        end

      %{} = field_map when map_size(field_map) > 1 ->
        entries = Map.to_list(field_map)
        {:multi_nested, entries}

      %{} ->
        {:simple, nil}
    end
  end

  defp atomize_field_name(field, resource) when is_binary(field) do
    if ResourceInfo.typescript_resource?(resource) do
      case ResourceInfo.get_original_field_name(resource, field) do
        original when is_atom(original) -> original
        _ -> field
      end
    else
      field
    end
  end

  defp atomize_field_name(%{} = map, resource) do
    Enum.into(map, %{}, fn {key, value} ->
      atomized_key = atomize_field_name(key, resource)
      atomized_value = atomize_nested_value(value, resource)
      {atomized_key, atomized_value}
    end)
  end

  defp atomize_field_name(field, _resource), do: field

  defp atomize_nested_value(value, resource) when is_list(value) do
    Enum.map(value, fn item -> atomize_field_name(item, resource) end)
  end

  defp atomize_nested_value(%{args: _} = value, _resource), do: value
  defp atomize_nested_value(%{"args" => _} = value, _resource), do: value
  defp atomize_nested_value(%{fields: _} = value, _resource), do: value
  defp atomize_nested_value(%{"fields" => _} = value, _resource), do: value
  defp atomize_nested_value(%{} = value, resource), do: atomize_field_name(value, resource)
  defp atomize_nested_value(value, _resource), do: value

  # Extracts args and fields from a map, handling both atom and string keys.
  # Returns {:ok, args, fields} or :not_args_structure.
  defp get_args_and_fields(map) when is_map(map) do
    args = Map.get(map, :args) || Map.get(map, "args")
    has_fields_key = Map.has_key?(map, :fields) || Map.has_key?(map, "fields")

    cond do
      args != nil ->
        fields =
          cond do
            Map.has_key?(map, :fields) -> Map.get(map, :fields)
            Map.has_key?(map, "fields") -> Map.get(map, "fields")
            true -> nil
          end

        {:ok, args, fields}

      has_fields_key ->
        fields = Map.get(map, :fields) || Map.get(map, "fields")
        {:ok, nil, fields}

      true ->
        :not_args_structure
    end
  end

  defp resolve_resource_field_name(resource, field_name) when is_binary(field_name) do
    if ResourceInfo.typescript_resource?(resource) do
      case ResourceInfo.get_original_field_name(resource, field_name) do
        original when is_atom(original) -> original
        _ -> convert_to_field_atom(field_name)
      end
    else
      convert_to_field_atom(field_name)
    end
  end

  defp resolve_resource_field_name(resource, field_name) when is_atom(field_name) do
    ResourceInfo.get_original_field_name(resource, field_name)
  end

  defp convert_to_field_atom(field_name) do
    formatter = AshTypescript.Rpc.input_field_formatter()
    FieldFormatter.convert_to_field_atom(field_name, formatter)
  end

  defp requires_nested_selection?(type, type_constraints) do
    {unwrapped_type, constraints} =
      case type do
        {:array, inner} ->
          Introspection.unwrap_new_type(inner, Keyword.get(type_constraints, :items, []))

        t when is_atom(t) ->
          Introspection.unwrap_new_type(t, type_constraints)

        _ ->
          {type, type_constraints}
      end

    cond do
      # Embedded resources
      is_atom(unwrapped_type) && Introspection.is_embedded_resource?(unwrapped_type) ->
        true

      # Ash.Type.Struct with instance_of pointing to an Ash resource
      unwrapped_type == Ash.Type.Struct && Introspection.is_resource_instance_of?(constraints) ->
        true

      # Union types
      unwrapped_type == Ash.Type.Union ->
        true

      # Tuple types - always require field selection
      unwrapped_type == Ash.Type.Tuple ->
        Introspection.has_field_constraints?(constraints)

      # Keyword types with field constraints
      unwrapped_type == Ash.Type.Keyword ->
        Introspection.has_field_constraints?(constraints)

      # Types with field constraints (Map, Struct with fields, TypedStruct)
      Introspection.has_field_constraints?(constraints) ->
        true

      true ->
        false
    end
  end

  defp get_field_specs(constraints) do
    case Keyword.get(constraints, :fields) do
      nil -> get_in(constraints, [:items, :fields]) || []
      fields -> fields
    end
  end

  defp build_load_spec(field_name, nested_select, nested_load) do
    load_fields =
      case nested_load do
        [] -> nested_select
        _ -> nested_select ++ nested_load
      end

    {field_name, load_fields}
  end

  defp format_extraction_template(template) do
    {atoms, keyword_pairs} =
      Enum.reduce(template, {[], []}, fn item, {atoms, kw_pairs} ->
        case item do
          {key, value} when is_atom(key) and is_map(value) ->
            {atoms, kw_pairs ++ [{key, value}]}

          {key, value} when is_atom(key) ->
            {atoms, kw_pairs ++ [{key, format_extraction_template(value)}]}

          atom when is_atom(atom) ->
            {atoms ++ [atom], kw_pairs}

          other ->
            {atoms ++ [other], kw_pairs}
        end
      end)

    atoms ++ keyword_pairs
  end
end
