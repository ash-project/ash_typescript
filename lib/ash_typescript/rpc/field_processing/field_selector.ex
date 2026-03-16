# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
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
  | Ash Resource | `is_ash_resource?(type)` | `select_resource_fields/3` |
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
  @spec process(module(), atom(), list(), map() | nil, map()) ::
          {:ok, select_result()} | {:error, term()}
  def process(resource, action_name, requested_fields, resource_lookups \\ nil, _type_index \\ %{}) do
    action = lookup_action(resource, action_name, resource_lookups)

    if is_nil(action) do
      throw({:action_not_found, action_name})
    end

    {type, constraints} = action_to_type_spec(resource, action)

    {select, load, template} =
      select_fields(type, constraints, requested_fields, [], resource_lookups)

    formatted_template = format_extraction_template(template)

    {:ok, {select, load, formatted_template}}
  catch
    error_tuple -> {:error, error_tuple}
  end

  # Look up action from AshApiSpec action_lookup (spec actions have resolved returns).
  # Falls back to raw Ash action for non-RPC actions or when action_lookup is unavailable.
  defp lookup_action(resource, action_name, _resource_lookups) do
    otp_app = Mix.Project.config()[:app]
    action_lookup = AshTypescript.action_lookup(otp_app)

    case Map.get(action_lookup, {resource, action_name}) do
      %AshApiSpec.Action{} = spec_action -> spec_action
      nil -> Ash.Resource.Info.action(resource, action_name)
    end
  end

  @doc """
  Converts an action to its type specification.

  Returns `{type, constraints}` tuple representing the action's return type.
  Handles both raw Ash action structs and `%AshApiSpec.Action{}` structs.
  """
  @spec action_to_type_spec(module(), map()) ::
          {AshApiSpec.Type.t() | nil, keyword()}
  def action_to_type_spec(resource, action) do
    resource_type = %AshApiSpec.Type{
      kind: :resource,
      module: resource,
      resource_module: resource,
      constraints: []
    }

    case action.type do
      type when type in [:create, :update, :destroy] ->
        {resource_type, []}

      :read ->
        if action.get? do
          {resource_type, []}
        else
          {%AshApiSpec.Type{kind: :array, item_type: resource_type, constraints: []}, []}
        end

      :action ->
        case action.returns do
          nil -> {%AshApiSpec.Type{kind: :any, module: nil, constraints: []}, []}
          %AshApiSpec.Type{} = type -> {type, []}
          type when is_atom(type) ->
            {AshApiSpec.Generator.TypeResolver.resolve(type, Map.get(action, :constraints) || []), []}
          type -> {type, []}
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
  @spec select_fields(
          atom() | tuple() | AshApiSpec.Type.t(),
          keyword(),
          list(),
          list(),
          map() | nil,
          map()
        ) ::
          select_result()

  # Header for default values
  def select_fields(
        type,
        constraints,
        requested_fields,
        path,
        resource_lookups \\ nil,
        _type_index \\ %{}
      )

  # %Type{kind} dispatch — passes type_info directly to handlers
  def select_fields(
        %AshApiSpec.Type{} = type_info,
        _constraints,
        requested_fields,
        path,
        resource_lookups,
        _type_index
      ) do
    inst = type_info.instance_of || type_info.module

    case type_info.kind do
      :type_ref ->
        full_type = AshApiSpec.Generator.TypeResolver.resolve_definition(type_info.module)
        select_fields(full_type, [], requested_fields, path, resource_lookups)

      :array ->
        select_fields(
          type_info.item_type,
          [],
          requested_fields,
          path,
          resource_lookups
        )

      kind when kind in [:resource, :embedded_resource] ->
        resource = type_info.resource_module || inst
        select_resource_fields(resource, requested_fields, path, resource_lookups)

      :union ->
        select_union_fields(type_info, requested_fields, path, "union_attribute")

      :tuple ->
        if has_typescript_field_names?(inst) do
          select_typed_struct_fields(type_info, requested_fields, path)
        else
          select_tuple_fields(type_info, requested_fields, path)
        end

      :keyword ->
        if has_typescript_field_names?(inst) do
          select_typed_struct_fields(type_info, requested_fields, path)
        else
          if has_spec_fields?(type_info) do
            select_typed_map_fields(type_info, requested_fields, path)
          else
            if requested_fields != [] do
              throw(
                {:invalid_field_selection, :primitive_type, type_info, requested_fields, path}
              )
            end

            {[], [], []}
          end
        end

      kind when kind in [:struct, :map] ->
        cond do
          inst && is_atom(inst) && is_ash_resource?(inst) ->
            select_resource_fields(inst, requested_fields, path, resource_lookups)

          has_typescript_field_names?(inst) ->
            select_typed_struct_fields(type_info, requested_fields, path)

          has_spec_fields?(type_info) ->
            error_type = if kind == :map, do: "map", else: "field_constrained_type"
            select_typed_map_fields(type_info, requested_fields, path, error_type)

          true ->
            if requested_fields != [] do
              throw(
                {:invalid_field_selection, :primitive_type, type_info, requested_fields, path}
              )
            end

            {[], [], []}
        end

      :any ->
        select_generic_fields(requested_fields, path)

      _ ->
        if requested_fields != [] do
          throw({:invalid_field_selection, :primitive_type, type_info, requested_fields, path})
        end

        {[], [], []}
    end
  end

  # {:array, inner_type} tuple form (from raw Ash types)
  def select_fields(
        {:array, inner_type},
        constraints,
        requested_fields,
        path,
        resource_lookups,
        _type_index
      ) do
    inner_constraints = Keyword.get(constraints, :items, [])

    select_fields(
      inner_type,
      inner_constraints,
      requested_fields,
      path,
      resource_lookups
    )
  end

  # Raw Ash type atoms — resolve to %AshApiSpec.Type{} and re-dispatch
  def select_fields(type, constraints, requested_fields, path, resource_lookups, _type_index)
      when is_atom(type) and not is_nil(type) do
    resolved = AshApiSpec.Generator.TypeResolver.resolve(type, constraints)
    select_fields(resolved, [], requested_fields, path, resource_lookups)
  end

  # Catch-all for unrecognized types
  def select_fields(_type, _constraints, requested_fields, path, _resource_lookups, _type_index) do
    if requested_fields != [] do
      throw({:invalid_field_selection, :primitive_type, nil, requested_fields, path})
    end

    {[], [], []}
  end

  # ---------------------------------------------------------------------------
  # Resource Field Selection
  # ---------------------------------------------------------------------------

  @doc """
  Selects fields from an Ash resource.

  Handles attributes, calculations, relationships, and aggregates.
  """
  def select_resource_fields(
        resource,
        requested_fields,
        path,
        resource_lookups \\ nil,
        _type_index \\ %{}
      ) do
    Validation.check_for_duplicates(requested_fields, path)

    Enum.reduce(requested_fields, {[], [], []}, fn field, acc ->
      field = atomize_field_name(field, resource)

      case parse_field_request(field) do
        {:simple, field_name} ->
          process_simple_resource_field(
            resource,
            field_name,
            path,
            acc,
            resource_lookups
          )

        {:nested, field_name, nested_fields} ->
          process_nested_resource_field(
            resource,
            field_name,
            nested_fields,
            path,
            acc,
            resource_lookups
          )

        {:with_args, calc_name, args, fields} ->
          process_calculation_with_args(
            resource,
            calc_name,
            args,
            fields,
            path,
            acc
          )

        {:multi_nested, entries} ->
          Enum.reduce(entries, acc, fn {field_name, nested_fields}, inner_acc ->
            cond do
              is_list(nested_fields) ->
                process_nested_resource_field(
                  resource,
                  field_name,
                  nested_fields,
                  path,
                  inner_acc,
                  resource_lookups
                )

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
                      inner_acc,
                      resource_lookups
                    )
                end

              true ->
                process_nested_resource_field(
                  resource,
                  field_name,
                  nested_fields,
                  path,
                  inner_acc,
                  resource_lookups
                )
            end
          end)
      end
    end)
  end

  defp process_simple_resource_field(
         resource,
         field_name,
         path,
         {select, load, template},
         resource_lookups
       ) do
    internal_name = resolve_resource_field_name(resource, field_name)

    {field_type, constraints, category} =
      get_resource_field_info(resource, internal_name, path, resource_lookups)

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
         {select, load, template},
         resource_lookups
       ) do
    internal_name = resolve_resource_field_name(resource, field_name)

    {field_type, field_constraints, category} =
      get_resource_field_info(resource, internal_name, path, resource_lookups)

    if category == :calculation_with_args do
      throw({:invalid_calculation_args, internal_name, path})
    end

    # Aggregates that don't return complex types don't support nested field selection
    if category == :aggregate &&
         !requires_nested_selection?(field_type, field_constraints) do
      throw({:invalid_field_selection, internal_name, :aggregate, path})
    end

    if category == :calculation && is_map(nested_fields) do
      throw({:invalid_calculation_args, internal_name, path})
    end

    if category == :calculation &&
         !requires_nested_selection?(field_type, field_constraints) do
      throw({:field_does_not_support_nesting, internal_name, path})
    end

    if category == :attribute &&
         !requires_nested_selection?(field_type, field_constraints) do
      throw({:field_does_not_support_nesting, internal_name, path})
    end

    # For union types (attributes or aggregates), nested_fields can be a map (member selection)
    is_union_type =
      case field_type do
        %AshApiSpec.Type{kind: :union} ->
          true

        _ ->
          {unwrapped_type, _} =
            AshApiSpec.Generator.TypeResolver.unwrap_new_type(field_type, field_constraints)

          unwrapped_type == Ash.Type.Union
      end

    if category == :union_attribute || is_union_type do
      if is_list(nested_fields) && nested_fields == [] do
        throw({:requires_field_selection, :union, internal_name, path})
      end
    else
      Validation.validate_non_empty(nested_fields, internal_name, path, category)
    end

    new_path = path ++ [internal_name]

    {nested_select, nested_load, nested_template} =
      select_fields(
        field_type,
        field_constraints,
        nested_fields,
        new_path,
        resource_lookups
      )

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
        dest_resource = extract_relationship_destination(field_type, resource, internal_name)

        unless dest_resource && ResourceInfo.typescript_resource?(dest_resource) do
          throw({:unknown_field, internal_name, resource, path})
        end

        load_spec = build_load_spec(internal_name, nested_select, nested_load)
        {select, load ++ [load_spec], template ++ [{internal_name, nested_template}]}

      cat when cat in [:calculation, :calculation_complex] ->
        load_spec = build_load_spec(internal_name, nested_select, nested_load)
        {select, load ++ [load_spec], template ++ [{internal_name, nested_template}]}

      :aggregate ->
        # Aggregates don't support nested loads - just load the aggregate itself
        # The template will handle extracting nested fields from the result
        {select, load ++ [internal_name], template ++ [{internal_name, nested_template}]}

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

    field_type = AshApiSpec.Generator.TypeResolver.resolve(calc.type, calc.constraints || [])
    new_path = path ++ [internal_name]
    is_complex_return_type = requires_nested_selection?(field_type, [])

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
          select_fields(field_type, [], fields, new_path)

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

  defp get_resource_field_info(resource, field_name, path, resource_lookups)
       when is_atom(resource) and is_map(resource_lookups) do
    api_resource = AshApiSpec.get_resource!(resource_lookups, resource)
    get_resource_field_info_from_spec(api_resource, resource, field_name, path)
  end

  defp get_resource_field_info(resource, field_name, path, _nil_lookups) when is_atom(resource) do
    api_resource = AshApiSpec.Generator.ResourceBuilder.build(resource)
    get_resource_field_info_from_spec(api_resource, resource, field_name, path)
  end

  defp get_resource_field_info_from_spec(api_resource, resource, field_name, path) do
    case Map.get(api_resource.fields, field_name) do
      %AshApiSpec.Field{kind: kind, type: type_info} = field ->
        case kind do
          :calculation ->
            category =
              cond do
                has_any_arguments?(field) ->
                  :calculation_with_args

                requires_nested_selection?(type_info, []) ->
                  :calculation_complex

                true ->
                  :calculation
              end

            {type_info, [], category}

          :attribute ->
            # Use the type info to classify - use the fallback classifier
            # since it handles all the nested selection logic correctly
            category = classify_attribute_category_from_type(type_info)
            {type_info, [], category}

          :aggregate ->
            {type_info, [], :aggregate}
        end

      nil ->
        case Map.get(api_resource.relationships, field_name) do
          %AshApiSpec.Relationship{destination: dest, cardinality: cardinality} ->
            dest_type = %AshApiSpec.Type{
              kind: :resource,
              name: "Resource",
              module: dest,
              resource_module: dest,
              constraints: []
            }

            type =
              if cardinality == :many do
                %AshApiSpec.Type{
                  kind: :array,
                  name: "Array",
                  item_type: dest_type,
                  constraints: []
                }
              else
                dest_type
              end

            {type, [], :relationship}

          nil ->
            throw({:unknown_field, field_name, resource, path})
        end
    end
  end

  defp classify_attribute_category_from_type(%AshApiSpec.Type{kind: :type_ref} = type_info) do
    full_type = AshApiSpec.Generator.TypeResolver.resolve_definition(type_info.module)
    classify_attribute_category_from_type(full_type)
  end

  defp classify_attribute_category_from_type(%AshApiSpec.Type{} = type_info) do
    # For array types, classify based on the inner type
    effective_type = if type_info.kind == :array, do: type_info.item_type, else: type_info

    case effective_type do
      %AshApiSpec.Type{kind: :type_ref} = ref ->
        full_type = AshApiSpec.Generator.TypeResolver.resolve_definition(ref.module)
        classify_attribute_category_from_type(full_type)

      %AshApiSpec.Type{kind: kind} when kind in [:resource, :embedded_resource] ->
        :embedded_resource

      %AshApiSpec.Type{kind: :union} ->
        :union_attribute

      %AshApiSpec.Type{kind: :tuple} ->
        :tuple

      %AshApiSpec.Type{kind: kind} = t
      when kind in [:struct, :map, :keyword] ->
        if has_spec_fields?(t) do
          :field_constrained_type
        else
          :attribute
        end

      _ ->
        :attribute
    end
  end

  defp has_any_arguments?(calc) do
    case calc.arguments do
      [] -> false
      nil -> false
      args when is_list(args) -> args != []
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
  def select_typed_struct_fields(type_or_constraints, requested_fields, path, _type_index \\ %{})

  def select_typed_struct_fields(
        %AshApiSpec.Type{} = type_info,
        requested_fields,
        path,
        _type_index
      ) do
    if requested_fields == [] do
      throw({:requires_field_selection, :field_constrained_type, nil})
    end

    inst = type_info.instance_of || type_info.module
    reverse_map = get_typescript_field_names_reverse(inst)
    {field_source, fields} = get_type_fields(type_info)

    Validation.check_for_duplicates(requested_fields, path)

    Enum.reduce(requested_fields, {[], [], []}, fn field, {select, load, template} ->
      case parse_field_request(field) do
        {:simple, field_name} ->
          internal_name = resolve_typed_struct_field(field_name, reverse_map)
          validate_field_exists_for_source!(internal_name, field_source, fields, path)
          {select, load, template ++ [internal_name]}

        {:nested, field_name, nested_fields} ->
          internal_name = resolve_typed_struct_field(field_name, reverse_map)
          validate_field_exists_for_source!(internal_name, field_source, fields, path)

          sub_type = find_field_type(field_source, fields, internal_name)
          new_path = path ++ [internal_name]

          {_nested_select, _nested_load, nested_template} =
            select_fields(sub_type, [], nested_fields, new_path)

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
        type_or_constraints,
        requested_fields,
        path,
        error_type \\ "field_constrained_type"
      )

  def select_typed_map_fields(
        %AshApiSpec.Type{} = type_info,
        requested_fields,
        path,
        error_type
      ) do
    {field_source, fields} = get_type_fields(type_info)

    if fields == [] do
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
            validate_field_exists_for_source!(internal_name, field_source, fields, path, error_type)
            {select, load, template ++ [internal_name]}

          {:nested, field_name, nested_fields} ->
            internal_name = convert_to_field_atom(field_name)
            validate_field_exists_for_source!(internal_name, field_source, fields, path, error_type)

            sub_type = find_field_type(field_source, fields, internal_name)
            new_path = path ++ [internal_name]

            {_nested_select, _nested_load, nested_template} =
              select_fields(sub_type, [], nested_fields, new_path)

            {select, load, template ++ [{internal_name, nested_template}]}

          {:with_args, _calc_name, _args, _fields} ->
            throw({:invalid_field_format, field, path})

          {:multi_nested, entries} ->
            Enum.reduce(entries, {select, load, template}, fn {field_name, nested}, {s, l, t} ->
              internal_name = convert_to_field_atom(field_name)
              validate_field_exists_for_source!(internal_name, field_source, fields, path, error_type)

              sub_type = find_field_type(field_source, fields, internal_name)
              new_path = path ++ [internal_name]

              {_nested_select, _nested_load, nested_template} =
                select_fields(sub_type, [], nested, new_path)

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
  def select_tuple_fields(%AshApiSpec.Type{} = type_info, requested_fields, path) do
    {field_source, fields} = get_type_fields(type_info)
    field_names = get_field_names(field_source, fields)

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

            unless field_name_exists?(field_source, fields, field_atom) do
              throw({:unknown_field, field_atom, "tuple", path})
            end

            index = Enum.find_index(field_names, &(&1 == field_atom))
            {select, load, template ++ [%{field_name: field_atom, index: index}]}

          {:nested, field_name, nested_fields} ->
            field_atom = convert_to_field_atom(field_name)

            unless field_name_exists?(field_source, fields, field_atom) do
              throw({:unknown_field, field_atom, "tuple", path})
            end

            sub_type = find_field_type(field_source, fields, field_atom)
            new_path = path ++ [field_atom]

            {_nested_select, _nested_load, nested_template} =
              select_fields(sub_type, [], nested_fields, new_path)

            {select, load, template ++ [{field_name, nested_template}]}

          {:multi_nested, entries} ->
            Enum.reduce(entries, {select, load, template}, fn {field_name, nested_fields},
                                                              {s, l, t} ->
              field_atom = convert_to_field_atom(field_name)

              unless field_name_exists?(field_source, fields, field_atom) do
                throw({:unknown_field, field_atom, "tuple", path})
              end

              index = Enum.find_index(field_names, &(&1 == field_atom))

              if is_list(nested_fields) do
                sub_type = find_field_type(field_source, fields, field_atom)
                new_path = path ++ [field_atom]

                {_nested_select, _nested_load, nested_template} =
                  select_fields(sub_type, [], nested_fields, new_path)

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
  def select_union_fields(
        type_or_constraints,
        requested_fields,
        path,
        error_type \\ "union_type",
        _type_index \\ %{}
      )

  def select_union_fields(
        %AshApiSpec.Type{} = type_info,
        requested_fields,
        path,
        error_type,
        _type_index
      ) do
    members = type_info.members || []
    normalized_fields = normalize_union_fields(requested_fields)

    Validation.validate_non_empty(normalized_fields, "union", path, :union)
    Validation.check_for_duplicates(normalized_fields, path)

    {load_items, template_items} =
      Enum.reduce(normalized_fields, {[], []}, fn field, {load_acc, template_acc} ->
        case parse_field_request(field) do
          {:simple, member_name} ->
            process_simple_union_member_spec(
              member_name,
              members,
              path,
              error_type,
              load_acc,
              template_acc
            )

          {:nested, member_name, nested_fields} ->
            process_nested_union_member_spec(
              member_name,
              nested_fields,
              members,
              path,
              error_type,
              load_acc,
              template_acc
            )

          {:multi_nested, entries} ->
            Enum.reduce(entries, {load_acc, template_acc}, fn {member_name, nested_fields},
                                                              {l_acc, t_acc} ->
              process_nested_union_member_spec(
                member_name,
                nested_fields,
                members,
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



  # Spec-based union member processing (uses %{name, type: %AshApiSpec.Type{}} members)

  defp process_simple_union_member_spec(
         member_name,
         members,
         path,
         error_type,
         load_acc,
         template_acc
       ) do
    internal_name = convert_union_member_name(member_name)
    member = find_union_member_spec(members, internal_name)

    unless member do
      throw({:unknown_field, internal_name, error_type, path})
    end

    # Check if member requires nested selection (embedded resources, typed maps, etc.)
    if requires_nested_selection?(member.type, []) do
      throw({:requires_field_selection, :complex_type, internal_name, path})
    end

    {load_acc, template_acc ++ [internal_name]}
  end

  defp process_nested_union_member_spec(
         member_name,
         nested_fields,
         members,
         path,
         error_type,
         load_acc,
         template_acc
       ) do
    internal_name = convert_union_member_name(member_name)
    member = find_union_member_spec(members, internal_name)

    unless member do
      throw({:unknown_field, internal_name, error_type, path})
    end

    new_path = path ++ [internal_name]

    {_nested_select, nested_load, nested_template} =
      select_fields(
        member.type,
        [],
        nested_fields,
        new_path,
        nil
      )

    if nested_load != [] do
      {load_acc ++ [{internal_name, nested_load}],
       template_acc ++ [{member_name, nested_template}]}
    else
      {load_acc, template_acc ++ [{member_name, nested_template}]}
    end
  end

  defp find_union_member_spec(members, name) do
    Enum.find(members, fn m -> m.name == name end)
  end

  defp normalize_union_fields(%{} = map) when map_size(map) > 0, do: [map]
  defp normalize_union_fields(fields) when is_list(fields), do: fields
  defp normalize_union_fields(fields), do: fields

  defp convert_union_member_name(name) when is_atom(name), do: name

  defp convert_union_member_name(name) when is_binary(name) do
    formatter = AshTypescript.Rpc.input_field_formatter()
    FieldFormatter.parse_input_field(name, formatter)
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

  # Extracts relationship destination from AshApiSpec type info
  defp extract_relationship_destination(
         %AshApiSpec.Type{resource_module: dest},
         _resource,
         _name
       )
       when not is_nil(dest),
       do: dest

  defp extract_relationship_destination(
         %AshApiSpec.Type{item_type: %AshApiSpec.Type{resource_module: dest}},
         _resource,
         _name
       )
       when not is_nil(dest),
       do: dest

  defp extract_relationship_destination(%AshApiSpec.Type{}, _resource, _name), do: nil

  # Fallback for non-AshApiSpec types (atom resource modules, raw Ash types)
  defp extract_relationship_destination(_type, resource, internal_name) do
    rel = Ash.Resource.Info.relationship(resource, internal_name)
    rel && rel.destination
  end

  defp requires_nested_selection?(type, constraints, _type_index \\ %{})

  defp requires_nested_selection?(
         %AshApiSpec.Type{kind: :type_ref} = type_info,
         _type_constraints,
         _type_index
       ) do
    full_type = AshApiSpec.Generator.TypeResolver.resolve_definition(type_info.module)
    requires_nested_selection?(full_type, [])
  end

  defp requires_nested_selection?(%AshApiSpec.Type{} = type_info, _type_constraints, _type_index) do
    effective_type = if type_info.kind == :array, do: type_info.item_type, else: type_info

    case effective_type do
      %AshApiSpec.Type{kind: :type_ref} = ref ->
        full_type = AshApiSpec.Generator.TypeResolver.resolve_definition(ref.module)
        requires_nested_selection?(full_type, [])

      %AshApiSpec.Type{kind: kind} when kind in [:resource, :embedded_resource] ->
        true

      %AshApiSpec.Type{kind: :union} ->
        true

      %AshApiSpec.Type{kind: kind} = t when kind in [:tuple, :keyword, :struct, :map] ->
        has_spec_fields?(t)

      _ ->
        false
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

  # ---------------------------------------------------------------------------
  # Type checking helpers
  # ---------------------------------------------------------------------------

  defp is_ash_resource?(module) when is_atom(module) and not is_nil(module) do
    Code.ensure_loaded?(module) == true and Ash.Resource.Info.resource?(module)
  end

  defp is_ash_resource?(_), do: false

  defp is_embedded_resource?(module) when is_atom(module) and not is_nil(module) do
    Code.ensure_loaded?(module) == true and Ash.Resource.Info.resource?(module) and
      Ash.Resource.Info.embedded?(module)
  end

  defp is_embedded_resource?(_), do: false

  defp has_typescript_field_names?(nil), do: false

  defp has_typescript_field_names?(module) when is_atom(module) do
    Code.ensure_loaded?(module) == true and function_exported?(module, :typescript_field_names, 0)
  end

  defp has_typescript_field_names?(_), do: false


  defp get_typescript_field_names_reverse(module) do
    if has_typescript_field_names?(module) do
      module.typescript_field_names() |> Map.new() |> Enum.into(%{}, fn {k, v} -> {v, k} end)
    else
      %{}
    end
  end

  # ---------------------------------------------------------------------------
  # Spec field helpers (mirroring ValueFormatter patterns)
  # ---------------------------------------------------------------------------

  # Check if type has hydrated spec fields
  defp has_spec_fields?(%AshApiSpec.Type{fields: fields}) when is_list(fields) and fields != [],
    do: true

  defp has_spec_fields?(%AshApiSpec.Type{element_types: ets})
       when is_list(ets) and ets != [],
       do: true

  defp has_spec_fields?(_), do: false

  # Get the list of field descriptors from a type
  defp get_type_fields(%AshApiSpec.Type{fields: fields}) when is_list(fields) and fields != [],
    do: {:spec, fields}

  defp get_type_fields(%AshApiSpec.Type{element_types: ets})
       when is_list(ets) and ets != [],
       do: {:spec, ets}

  defp get_type_fields(_), do: {:none, []}

  # Look up a sub-field's type from spec fields (list of %{name, type, allow_nil?})
  defp find_spec_field_type(fields, field_name) do
    case Enum.find(fields, fn f -> f.name == field_name end) do
      %{type: type} -> type
      nil -> nil
    end
  end

  # Look up a sub-field's type from raw constraint fields (keyword list)
  defp find_raw_field_type(fields, field_name) do
    case Keyword.get(fields, field_name) do
      nil -> nil
      config when is_list(config) -> Keyword.get(config, :type)
      _ -> nil
    end
  end

  # Find sub-field type from either spec or raw field lists
  defp find_field_type(:spec, fields, field_name), do: find_spec_field_type(fields, field_name)

  defp find_field_type(:raw, fields, field_name) do
    case find_raw_field_type(fields, field_name) do
      nil -> nil
      raw_type -> resolve_raw_field_type(raw_type)
    end
  end

  defp find_field_type(:none, _fields, _field_name), do: nil

  # Resolve a raw Ash type atom to %AshApiSpec.Type{} for recursion
  defp resolve_raw_field_type(type) when is_atom(type) and not is_nil(type) do
    AshApiSpec.Generator.TypeResolver.resolve(type, [])
  end

  defp resolve_raw_field_type({:array, inner_type}) do
    AshApiSpec.Generator.TypeResolver.resolve({:array, inner_type}, [])
  end

  defp resolve_raw_field_type(_), do: nil

  # Get field names from either spec or raw field lists
  defp get_field_names(:spec, fields), do: Enum.map(fields, fn f -> f.name end)
  defp get_field_names(:raw, fields), do: Enum.map(fields, &elem(&1, 0))
  defp get_field_names(:none, _fields), do: []

  # Check if a field name exists in either spec or raw field lists
  defp field_name_exists?(:spec, fields, name) do
    Enum.any?(fields, fn f -> f.name == name end)
  end

  defp field_name_exists?(:raw, fields, name) do
    Keyword.has_key?(fields, name)
  end

  defp field_name_exists?(:none, _fields, _name), do: false

  # Validate a field exists in the appropriate field source, throwing on failure
  defp validate_field_exists_for_source!(name, field_source, fields, path, error_type \\ "field_constrained_type")

  defp validate_field_exists_for_source!(name, :spec, fields, path, error_type) do
    unless Enum.any?(fields, fn f -> f.name == name end) do
      throw({:unknown_field, name, error_type, path})
    end
  end

  defp validate_field_exists_for_source!(name, :raw, fields, path, error_type) do
    unless Keyword.has_key?(fields, name) do
      throw({:unknown_field, name, error_type, path})
    end
  end

  defp validate_field_exists_for_source!(name, :none, _fields, path, error_type) do
    throw({:unknown_field, name, error_type, path})
  end
end
