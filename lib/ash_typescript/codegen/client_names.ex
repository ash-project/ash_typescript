# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.ClientNames do
  @moduledoc false
  # The only codegen module that turns an Elixir name into a client name. It reads
  # `custom.ash_rpc` (written once by `AshRpc.Manifest.Decorator`) through
  # `AshRpc.Manifest.Custom`, so codegen emits exactly the names the runtime accepts.
  #
  # Resource and `:type_ref` nodes are resolved through `AshTypescript.resource_lookup/0`
  # and `AshTypescript.type_lookup/0`, which honour `AshTypescript.with_manifest/2`.
  # A miss, or a node without decoration, raises `ArgumentError`: there is no
  # formatter fallback, since codegen would otherwise emit a name the runtime rejects.

  alias Ash.Info.Manifest
  alias AshRpc.Manifest.Custom

  @doc "Client name of a resource field (attribute, calculation, aggregate or relationship)."
  @spec resource_field(Manifest.Resource.t() | module(), atom()) :: String.t()
  def resource_field(resource, field) when is_atom(field) do
    r = resource!(resource)
    fetch!(Custom.field_names(r), field, "resource #{inspect(r.module)}")
  end

  @doc "Client name of a calculation argument."
  @spec calculation_argument(Manifest.Resource.t() | module(), atom(), atom()) :: String.t()
  def calculation_argument(resource, calc, arg) when is_atom(calc) and is_atom(arg) do
    r = resource!(resource)

    r
    |> Custom.calculation_argument_names(calc)
    |> invert()
    |> fetch!(arg, "calculation #{inspect(calc)} on resource #{inspect(r.module)}")
  end

  @doc "Client name of an action input (argument or accepted attribute)."
  @spec action_input(Manifest.Resource.t() | module(), Manifest.Action.t(), atom()) ::
          String.t()
  def action_input(resource, %Manifest.Action{} = action, input) when is_atom(input) do
    where = "action #{inspect(action.name)} on resource #{inspect(resource_module(resource))}"

    case Custom.action_expected_input_keys(action) do
      nil ->
        raise ArgumentError,
              "#{where} is not decorated (no custom.ash_rpc expected_input_keys); " <>
                "cannot name input #{inspect(input)}"

      keys ->
        keys |> invert() |> fetch!(input, where)
    end
  end

  @doc """
  Client name of a field of a typed container, embedded resource or resource type.
  `:type_ref` nodes are resolved through the type lookup first.
  """
  @spec type_field(Manifest.Type.t(), atom()) :: String.t()
  def type_field(%Manifest.Type{} = type, field) when is_atom(field) do
    case resolve_type!(type) do
      %Manifest.Type{kind: kind} = t when kind in [:resource, :embedded_resource] ->
        resource_field(Manifest.Type.effective_resource(t), field)

      t ->
        if Custom.ash_rpc(t) do
          fetch!(Custom.type_field_names(t), field, describe(t))
        else
          raise ArgumentError,
                "#{describe(t)} is not decorated (no custom.ash_rpc); cannot name #{inspect(field)}"
        end
    end
  end

  @doc "Client name of a union member."
  @spec union_member(Manifest.Type.t(), atom()) :: String.t()
  def union_member(%Manifest.Type{} = type, member) when is_atom(member) do
    t = resolve_type!(type)

    if t.kind == :union and Custom.ash_rpc(t) do
      fetch!(Custom.type_member_names(t), member, describe(t))
    else
      raise ArgumentError,
            "#{describe(t)} is not a decorated union; cannot name member #{inspect(member)}"
    end
  end

  @doc "Client name of an exposed metadata field of a wire entrypoint."
  @spec metadata_field(AshRpc.Entrypoint.t(), atom()) :: String.t()
  def metadata_field(%AshRpc.Entrypoint{} = entrypoint, field) when is_atom(field) do
    fetch!(
      Custom.entrypoint_metadata_field_names(entrypoint),
      field,
      "metadata of entrypoint #{inspect(entrypoint.name)}"
    )
  end

  @doc "The decorated wire entrypoint for an RPC name."
  @spec wire_entrypoint!(atom() | String.t()) :: AshRpc.Entrypoint.t()
  def wire_entrypoint!(rpc_name) do
    name = to_string(rpc_name)

    case AshTypescript.manifest() |> AshRpc.Manifest.entrypoint_lookup() |> Map.get(name) do
      %AshRpc.Entrypoint{} = entrypoint -> entrypoint
      nil -> raise ArgumentError, "no wire entrypoint #{inspect(name)} in the manifest"
    end
  end

  @doc "Resolves a `:type_ref` to its named type; other types are returned as they are."
  @spec resolve_type!(Manifest.Type.t()) :: Manifest.Type.t()
  def resolve_type!(%Manifest.Type{kind: :type_ref, module: module}), do: named_type!(module)

  def resolve_type!(%Manifest.Type{} = type), do: type

  @doc "The decorated named type for a `:type_ref` module."
  @spec named_type!(module()) :: Manifest.Type.t()
  def named_type!(module) do
    Manifest.get_type(AshTypescript.type_lookup(), module) ||
      raise ArgumentError, "named type #{inspect(module)} is not in the manifest"
  end

  defp resource!(%Manifest.Resource{custom: %{ash_rpc: _}} = resource), do: resource
  defp resource!(%Manifest.Resource{module: module}), do: resource!(module)

  defp resource!(module) when is_atom(module) do
    case Map.get(AshTypescript.resource_lookup(), module) do
      %Manifest.Resource{custom: %{ash_rpc: _}} = resource ->
        resource

      nil ->
        raise ArgumentError, "resource #{inspect(module)} is not in the manifest"

      _ ->
        raise ArgumentError, "resource #{inspect(module)} is not decorated (no custom.ash_rpc)"
    end
  end

  defp fetch!(names, key, where) do
    case Map.fetch(names, key) do
      {:ok, name} ->
        name

      :error ->
        raise ArgumentError,
              "no client name for #{inspect(key)} on #{where}; " <>
                "codegen would emit a name the runtime rejects"
    end
  end

  defp invert(map), do: Map.new(map, fn {k, v} -> {v, k} end)

  defp describe(%Manifest.Type{} = t) do
    "type #{inspect(t.name)} (#{inspect(Manifest.Type.effective_module(t))}, kind #{inspect(t.kind)})"
  end

  defp resource_module(%Manifest.Resource{module: module}), do: module
  defp resource_module(module), do: module
end
