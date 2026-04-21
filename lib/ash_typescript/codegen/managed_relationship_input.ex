# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.ManagedRelationshipInput do
  @moduledoc """
  Derives TypeScript input types for action arguments driven by
  `manage_relationship` changes.

  When an action argument is `:map` (or `{:array, :map}`) without explicit
  `:fields` constraints but is referenced by a `manage_relationship` change,
  the default type mapper would emit `Record<string, any>`. This module
  inspects the relationship's destination resource and the reachable
  destination actions to build a typed TypeScript object instead.

  The approach mirrors `Ash.Changeset.ManagedRelationshipHelpers` (the same
  introspection entry point AshGraphql uses), and is opt-in via the
  `config :ash_typescript, :derive_managed_relationship_inputs?` flag
  (enabled by default).
  """

  alias Ash.Changeset.ManagedRelationshipHelpers
  alias AshTypescript.Codegen.TypeMapper

  @doc """
  Returns a TypeScript type string for `arg` if it is a map-typed argument
  driven by a `manage_relationship` change, otherwise returns `nil`.
  """
  @spec maybe_build_type(module(), map(), Ash.Resource.Actions.Argument.t()) ::
          String.t() | nil
  def maybe_build_type(resource, action, arg) do
    if Application.get_env(:ash_typescript, :derive_managed_relationship_inputs?, true) and
         map_like?(arg) do
      case find_manage_change(action, arg.name) do
        nil -> nil
        opts -> build_type(resource, arg, opts)
      end
    end
  end

  defp map_like?(%{type: type, constraints: constraints}) when type in [:map, Ash.Type.Map] do
    not Keyword.has_key?(constraints || [], :fields)
  end

  defp map_like?(%{type: {:array, inner}, constraints: constraints})
       when inner in [:map, Ash.Type.Map] do
    items = Keyword.get(constraints || [], :items, [])
    not Keyword.has_key?(items, :fields)
  end

  defp map_like?(_), do: false

  defp find_manage_change(action, arg_name) do
    action
    |> Map.get(:changes, [])
    |> Enum.find_value(fn
      %{change: {Ash.Resource.Change.ManageRelationship, opts}} ->
        if Keyword.get(opts, :argument) == arg_name, do: opts

      _ ->
        nil
    end)
  end

  defp build_type(resource, arg, manage_opts) do
    relationship_name = Keyword.get(manage_opts, :relationship)
    relationship = Ash.Resource.Info.relationship(resource, relationship_name)

    if relationship do
      case gather_fields(relationship, Keyword.get(manage_opts, :opts, [])) do
        [] -> nil
        fields -> render_fields(fields, arg.type)
      end
    end
  end

  defp gather_fields(relationship, manage_opts) do
    sanitized =
      relationship
      |> ManagedRelationshipHelpers.sanitize_opts(expand_type_defaults(manage_opts))

    destination_action_names =
      [
        ManagedRelationshipHelpers.on_match_destination_actions(sanitized, relationship),
        ManagedRelationshipHelpers.on_no_match_destination_actions(sanitized, relationship),
        ManagedRelationshipHelpers.on_missing_destination_actions(sanitized, relationship)
      ]
      |> Enum.flat_map(&List.wrap/1)
      |> Enum.flat_map(fn
        {:destination, action_name} when not is_nil(action_name) -> [action_name]
        _ -> []
      end)

    lookup_action_names =
      case ManagedRelationshipHelpers.on_lookup_read_action(sanitized, relationship) do
        {:destination, action_name} when not is_nil(action_name) -> [action_name]
        _ -> []
      end

    actions =
      (destination_action_names ++ lookup_action_names)
      |> Enum.uniq()
      |> Enum.map(&Ash.Resource.Info.action(relationship.destination, &1))
      |> Enum.reject(&is_nil/1)

    could_lookup? = ManagedRelationshipHelpers.could_lookup?(sanitized)
    could_match? = ManagedRelationshipHelpers.could_update?(sanitized)

    pkey_fields =
      if could_lookup? or could_match? do
        relationship.destination
        |> Ash.Resource.Info.primary_key()
        |> Enum.map(fn name ->
          attr = Ash.Resource.Info.attribute(relationship.destination, name)
          {name, attr, false}
        end)
        |> Enum.reject(fn {_, attr, _} -> is_nil(attr) end)
      else
        []
      end

    action_fields = Enum.flat_map(actions, &action_fields(relationship.destination, &1))

    reject = MapSet.new([relationship.destination_attribute])

    (pkey_fields ++ action_fields)
    |> Enum.reject(fn {name, _, _} -> MapSet.member?(reject, name) end)
    |> consolidate()
  end

  defp action_fields(destination, %{type: :create} = action) do
    accepted =
      (action.accept || [])
      |> Enum.map(fn name ->
        attr = Ash.Resource.Info.attribute(destination, name)
        allow_nil_input = Map.get(action, :allow_nil_input, []) || []

        required? =
          not is_nil(attr) and
            name not in allow_nil_input and
            not attr.allow_nil? and
            is_nil(attr.default)

        {name, attr, required?}
      end)
      |> Enum.reject(fn {_, attr, _} -> is_nil(attr) end)

    arguments = argument_fields(action)
    accepted ++ arguments
  end

  defp action_fields(destination, %{type: :update} = action) do
    require_attributes = Map.get(action, :require_attributes, []) || []
    allow_nil_input = Map.get(action, :allow_nil_input, []) || []

    accepted =
      (action.accept || [])
      |> Enum.map(fn name ->
        attr = Ash.Resource.Info.attribute(destination, name)

        required? =
          not is_nil(attr) and name in require_attributes and name not in allow_nil_input

        {name, attr, required?}
      end)
      |> Enum.reject(fn {_, attr, _} -> is_nil(attr) end)

    arguments = argument_fields(action)
    accepted ++ arguments
  end

  defp action_fields(_destination, %{type: :read} = action) do
    argument_fields(action)
  end

  defp action_fields(_destination, _), do: []

  # `manage_relationship(:arg, :rel, type: :create)` and the like are shorthand
  # for a full set of on_* options. `ManagedRelationshipHelpers.sanitize_opts/2`
  # only fills in action names for the on_* options that were explicitly
  # provided, so we expand the shorthand here first (mirroring AshGraphql).
  defp expand_type_defaults(manage_opts) do
    case Keyword.get(manage_opts, :type) do
      nil ->
        manage_opts

      type when type in [:append_and_remove, :append, :remove, :direct_control, :create] ->
        defaults = Ash.Changeset.manage_relationship_opts(type)

        Enum.reduce(defaults, manage_opts, fn {key, value}, acc ->
          Keyword.put_new(acc, key, value)
        end)

      _ ->
        manage_opts
    end
  end

  defp argument_fields(action) do
    action.arguments
    |> Enum.filter(& &1.public?)
    |> Enum.map(fn arg ->
      required? = not arg.allow_nil? and is_nil(arg.default)
      {arg.name, arg, required?}
    end)
  end

  # When the same field surfaces from multiple actions, mark it required only
  # if every source requires it; otherwise treat it as optional. Retain the
  # first occurrence so the type/allow_nil? metadata is stable.
  defp consolidate(fields) do
    fields
    |> Enum.group_by(fn {name, _, _} -> name end)
    |> Enum.map(fn {_name, entries} ->
      {name, first_meta, _} = hd(entries)
      all_required? = Enum.all?(entries, fn {_, _, required?} -> required? end)
      {name, first_meta, all_required?}
    end)
    |> Enum.sort_by(fn {name, _, _} -> to_string(name) end)
  end

  defp render_fields(fields, arg_type) do
    field_strings =
      Enum.map(fields, fn {name, meta, required?} ->
        formatted_name =
          AshTypescript.FieldFormatter.format_field_name(
            name,
            AshTypescript.Rpc.output_field_formatter()
          )

        base_type = TypeMapper.get_ts_input_type(meta)
        allow_nil? = Map.get(meta, :allow_nil?, true)
        ts_type = if allow_nil?, do: "#{base_type} | null", else: base_type
        marker = if required?, do: "", else: "?"
        "#{formatted_name}#{marker}: #{ts_type}"
      end)

    inner = "{ " <> Enum.join(field_strings, "; ") <> " }"

    case arg_type do
      {:array, t} when t in [:map, Ash.Type.Map] -> "Array<#{inner}>"
      _ -> inner
    end
  end
end
