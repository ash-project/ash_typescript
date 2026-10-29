# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.ScalarAliases do
  @moduledoc """
  The TypeScript alias names of scalars: scalar custom types (a `kind:
  :unknown` use of a `use Ash.Type` module, with a `scalar` entry or
  `typescript_type/0`) and NewTypes over primitives (a definition whose kind
  the kind table maps, such as `:string` or `:integer`; not enums, arrays,
  unions, containers or resources, and not a NewType over a scalar custom
  type).

  `name/2` takes the node `TypeMapper` maps the scalar from (the `:unknown`
  use, or the NewType's definition) and returns the first of:

    1. the `ts_alias` of the module's manifest `scalar` entry: a string, or an
       MFA called with the node's constraints, whose `nil` keeps that use
       inline with no fallback;
    2. the type's `typescript_type_alias/0`;
    3. the `ts_alias` of a built-in `scalar` entry
       (`AshTypescript.CustomTypes.Builtin`: ULID, Ltree), with the same rule,
       when the manifest has no `scalar` entry for the module (a manifest
       entry replaces the built-in whole);
    4. the joined module name under `alias_all_types?`, except for an entry
       with an MFA `ts_type` and no `ts_alias` (its TypeScript varies by use),
       and for a NewType over a kind that maps to `any` (`:term`, `:any`);

  else `nil`. A scalar's alias body is its TypeScript by the existing
  precedence (entry `ts_type`, `typescript_type/0`, built-in, base type), so
  `typescript_type/0` combines with any alias opt-in. A name applies at every
  position that renders the scalar; zod and valibot schemas stay inline.
  """

  alias Ash.Info.Manifest.Type
  alias AshTypescript.Codegen.{Helpers, TypeMapper}
  alias AshTypescript.CustomTypes
  alias AshTypescript.CustomTypes.Scalar

  @doc """
  The alias name of the scalar `node` (see the module doc), or `nil`.
  `custom_types` is the persisted `t:AshTypescript.CustomTypes.custom_types/0`.
  Raises `ArgumentError` for an invalid `typescript_type_alias/0` result
  (`AshTypescript.CustomTypes.check_alias_names/2` reports it at compile
  time) or an MFA `ts_alias` result that isn't a string or `nil`.
  """
  @spec name(Type.t(), CustomTypes.custom_types()) :: String.t() | nil
  def name(%Type{module: module} = node, custom_types) do
    case source(node, custom_types) do
      nil ->
        nil

      {:entry, entry} ->
        CustomTypes.mapping(entry, :ts_alias, node.constraints)

      :callback ->
        case CustomTypes.callback_alias_name(module) do
          {:ok, name} -> name
          {:error, message} -> raise ArgumentError, message
        end

      :joined ->
        Helpers.module_type_name(module)
    end
  end

  @doc false
  # What names the scalar `node`: `{:entry, entry}` (its `ts_alias`),
  # `:callback`, `:joined`, or `nil` when it isn't aliased (or isn't a
  # scalar). Lets compile-time checks tell the sources apart without calling
  # an MFA.
  @spec source(Type.t(), CustomTypes.custom_types()) ::
          {:entry, Scalar.t()} | :callback | :joined | nil
  def source(%Type{module: module} = node, %{declared: declared, builtin: builtin} = custom_types) do
    if scalar_node?(node) do
      declared = scalar_entry(Map.get(declared, module))
      builtin = scalar_entry(Map.get(builtin, module))

      cond do
        declared && declared.ts_alias -> {:entry, declared}
        exports?(module, :typescript_type_alias, 0) -> :callback
        declared -> joined(node, declared, custom_types)
        builtin && builtin.ts_alias -> {:entry, builtin}
        true -> joined(node, builtin, custom_types)
      end
    end
  end

  defp joined(%Type{kind: kind}, entry, custom_types) do
    cond do
      not Map.get(custom_types, :alias_all_types?, false) -> nil
      match?(%Scalar{ts_type: {_m, _f, _a}}, entry) -> nil
      kind != :unknown and not TypeMapper.aliasable_kind?(kind) -> nil
      true -> :joined
    end
  end

  # A `kind: :unknown` node of a module that isn't a NewType, or a NewType's
  # definition with a primitive kind. Modules of the primitive table
  # (`Ash.Type.UtcDatetime`, …) map before any entry and are never aliased.
  defp scalar_node?(%Type{module: module, kind: kind})
       when is_atom(module) and not is_nil(module) do
    cond do
      TypeMapper.primitive_module?(module) -> false
      kind == :unknown -> not new_type?(module)
      TypeMapper.primitive_kind?(kind) -> new_type?(module)
      true -> false
    end
  end

  defp scalar_node?(_node), do: false

  defp scalar_entry(%Scalar{} = entry), do: entry
  defp scalar_entry(_other), do: nil

  defp new_type?(module),
    do: Code.ensure_loaded?(module) and Ash.Type.NewType.new_type?(module)

  defp exports?(module, function, arity),
    do: Code.ensure_loaded?(module) and function_exported?(module, function, arity)
end
