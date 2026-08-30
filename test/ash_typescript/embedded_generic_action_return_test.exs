# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.EmbeddedGenericActionReturnTest do
  @moduledoc """
  Regression coverage for embedded resources that are only reachable through a
  generic action's `:returns` type (or through a generic action argument).

  These used to be referenced by the generated RPC file but never defined in the
  types file, so the output did not compile — the only workaround was adding a
  dummy calculation to make the embedded resource reachable some other way.
  Reachability now walks generic action return types, so the schema is emitted.

  The domain, resources and manifest are declared inline rather than added to
  `test/support` so the committed `test/ts` fixtures stay untouched — the point
  is to prove reachability, not to grow the shared fixture set.
  """

  # Mutates the global :manifest config, so must not run async.
  use ExUnit.Case, async: false

  @moduletag :ash_typescript

  defmodule StructReturnEmbedded do
    use Ash.Resource, data_layer: :embedded, domain: nil, extensions: [AshTypescript.Resource]

    typescript do
      type_name "StructReturnEmbedded"
    end

    attributes do
      uuid_primary_key :id
      attribute :label, :string, public?: true, allow_nil?: false
    end
  end

  defmodule ArrayReturnEmbedded do
    use Ash.Resource, data_layer: :embedded, domain: nil, extensions: [AshTypescript.Resource]

    typescript do
      type_name "ArrayReturnEmbedded"
    end

    attributes do
      uuid_primary_key :id
      attribute :label, :string, public?: true, allow_nil?: false
    end
  end

  defmodule ArgumentEmbedded do
    use Ash.Resource, data_layer: :embedded, domain: nil, extensions: [AshTypescript.Resource]

    typescript do
      type_name "ArgumentEmbedded"
    end

    attributes do
      uuid_primary_key :id
      attribute :label, :string, public?: true, allow_nil?: false
    end
  end

  defmodule Holder do
    use Ash.Resource,
      domain: AshTypescript.EmbeddedGenericActionReturnTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "Holder"
    end

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end

    actions do
      defaults [:read]

      # Embedded resource reachable *only* through this action's return type.
      action :build_struct, :struct do
        public? true

        constraints instance_of:
                      AshTypescript.EmbeddedGenericActionReturnTest.StructReturnEmbedded

        run fn _input, _ctx ->
          {:ok, %AshTypescript.EmbeddedGenericActionReturnTest.StructReturnEmbedded{}}
        end
      end

      action :build_struct_list, {:array, :struct} do
        public? true

        constraints items: [
                      instance_of:
                        AshTypescript.EmbeddedGenericActionReturnTest.ArrayReturnEmbedded
                    ]

        run fn _input, _ctx -> {:ok, []} end
      end

      action :accept_struct, :string do
        public? true

        argument :payload, :struct,
          allow_nil?: false,
          constraints: [
            instance_of: AshTypescript.EmbeddedGenericActionReturnTest.ArgumentEmbedded
          ]

        run fn _input, _ctx -> {:ok, "ok"} end
      end
    end
  end

  defmodule Domain do
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource AshTypescript.EmbeddedGenericActionReturnTest.Holder do
        rpc_action :list_holders, :read
        rpc_action :build_struct, :build_struct
        rpc_action :build_struct_list, :build_struct_list
        rpc_action :accept_struct, :accept_struct
      end
    end

    resources do
      resource AshTypescript.EmbeddedGenericActionReturnTest.Holder
    end
  end

  defmodule Manifest do
    use AshTypescript.Manifest,
      otp_app: :ash_typescript,
      domains: [AshTypescript.EmbeddedGenericActionReturnTest.Domain]
  end

  # Codegen resolves resources through `Ash.Info.domains/1`, so generation runs
  # against a dedicated otp_app to keep the shared test domains out of the way.
  @otp_app :embedded_generic_action_return_test_app

  setup do
    overrides = [manifest: Manifest, typed_controllers: [], typed_channels: []]

    previous =
      Enum.map(overrides, fn {key, value} ->
        prev = Application.get_env(:ash_typescript, key)
        Application.put_env(:ash_typescript, key, value)
        {key, prev}
      end)

    Application.put_env(@otp_app, :ash_domains, [Domain])

    on_exit(fn ->
      Enum.each(previous, fn {key, prev} -> Application.put_env(:ash_typescript, key, prev) end)
      Application.delete_env(@otp_app, :ash_domains)
    end)

    {:ok, files} = AshTypescript.Codegen.Orchestrator.generate(@otp_app, [])

    types_content =
      files
      |> Enum.filter(fn {path, _} -> String.ends_with?(path, "ash_types.ts") end)
      |> Enum.map_join("\n", fn {_, content} -> content end)

    rpc_content =
      files
      |> Enum.filter(fn {path, _} -> String.ends_with?(path, "generated.ts") end)
      |> Enum.map_join("\n", fn {_, content} -> content end)

    refute types_content == "", "no types file was generated"
    refute rpc_content == "", "no RPC file was generated"

    %{types: types_content, rpc: rpc_content}
  end

  test "embedded resource returned by a generic action is defined, not just referenced", %{
    types: types,
    rpc: rpc
  } do
    assert types =~ "export type StructReturnEmbeddedResourceSchema = {"
    assert rpc =~ "StructReturnEmbeddedResourceSchema"
  end

  test "embedded resource in a generic action's array return type is defined", %{
    types: types,
    rpc: rpc
  } do
    assert types =~ "export type ArrayReturnEmbeddedResourceSchema = {"
    assert rpc =~ "ArrayReturnEmbeddedResourceSchema"
  end

  test "embedded resource used as a generic action argument is defined", %{types: types} do
    assert types =~ "export type ArgumentEmbeddedInputSchema = {"
  end

  test "every embedded schema the RPC file imports from the types file exists there", %{
    types: types,
    rpc: rpc
  } do
    imported =
      Regex.scan(~r/import type \{([^}]*)\} from "\.\/ash_types"/, rpc)
      |> Enum.flat_map(fn [_, names] -> String.split(names, ",") end)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    refute imported == [], "expected the RPC file to import types from the types file"

    missing = Enum.reject(imported, &String.contains?(types, "export type #{&1}"))

    assert missing == [],
           "RPC file imports names that the types file never defines: #{inspect(missing)}"
  end
end
