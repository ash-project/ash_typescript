# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.VerifyRpcActionOptionsTest.Item do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshTypescript.Resource]

  typescript do
    type_name "VerifyActionOptionsItem"
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  actions do
    defaults [:read, create: [:name]]
  end
end

defmodule AshTypescript.Rpc.VerifyRpcActionOptionsTest do
  @moduledoc """
  `AshTypescript.Manifest.Verifiers.VerifyRpc`'s checks of an rpc_action's
  action and its `get?`, `get_by`, `allowed_loads` and `denied_loads`
  options, and of duplicate rpc_action and typed query names.
  """
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc.VerifyRpcActionOptionsTest.Item

  defp verify(rpc_block) do
    name = Module.concat(__MODULE__, "D#{System.unique_integer([:positive])}")

    {_, _stderr} =
      ExUnit.CaptureIO.with_io(:standard_error, fn ->
        Module.create(
          name,
          quote do
            use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

            typescript_rpc do
              resource Item do
                unquote(rpc_block)
              end
            end

            resources do
              resource Item
            end
          end,
          Macro.Env.location(__ENV__)
        )
      end)

    {result, _stderr} =
      ExUnit.CaptureIO.with_io(:standard_error, fn ->
        AshTypescript.Manifest.verify_for_domains([name])
      end)

    result
  end

  test "an action the resource doesn't have" do
    assert {:error, message} = verify(quote(do: rpc_action(:list_missing, :missing)))

    assert message =~
             "RPC action list_missing references action missing, which does not exist on resource #{inspect(Item)}"
  end

  test "get? on a non-read action" do
    assert {:error, message} = verify(quote(do: rpc_action(:make_item, :create, get?: true)))

    assert message =~
             "RPC action make_item: get? option can only be used on read actions, but create is a create action"
  end

  test "get_by on a non-read action" do
    assert {:error, message} = verify(quote(do: rpc_action(:make_item, :create, get_by: [:name])))

    assert message =~
             "RPC action make_item: get_by option can only be used on read actions, but create is a create action"
  end

  test "get? with get_by" do
    assert {:error, message} =
             verify(quote(do: rpc_action(:get_item, :read, get?: true, get_by: [:name])))

    assert message =~
             "RPC action get_item: get? and get_by options are mutually exclusive. Use get? to fetch by primary key, or get_by to fetch by specific fields."
  end

  test "get_by fields that aren't attributes" do
    assert {:error, message} = verify(quote(do: rpc_action(:get_item, :read, get_by: [:nope])))

    assert message =~
             "RPC action get_item: get_by contains invalid fields: [:nope]. These must be valid attribute names on the resource."
  end

  test "allowed_loads with denied_loads" do
    assert {:error, message} =
             verify(
               quote(do: rpc_action(:list_items, :read, allowed_loads: [], denied_loads: []))
             )

    assert message =~
             "RPC action list_items: allowed_loads and denied_loads options are mutually exclusive. Use allowed_loads to restrict loading to specific fields, or denied_loads to block specific fields."
  end

  test "two rpc_actions with one name fail while the manifest is built" do
    assert_raise RuntimeError, ~r/duplicate wire entrypoint name "list_items"/, fn ->
      verify(
        quote do
          rpc_action :list_items, :read
          rpc_action :list_items, :read
        end
      )
    end
  end

  test "two typed queries with one name" do
    assert {:error, message} =
             verify(
               quote do
                 typed_query :item_names, :read do
                   fields [:name]
                 end

                 typed_query :item_names, :read do
                   fields [:id]
                 end
               end
             )

    assert message =~ "Duplicate RPC typed queries found: [:item_names]"
  end

  test "valid options pass" do
    assert :ok =
             verify(
               quote do
                 rpc_action :get_item, :read, get_by: [:name]
                 rpc_action :list_items, :read, denied_loads: []
               end
             )
  end
end
