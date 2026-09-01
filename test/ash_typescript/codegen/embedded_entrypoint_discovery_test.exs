# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.EmbeddedEntrypointDiscoveryTest do
  @moduledoc """
  Regression coverage for embedded resource discovery being scoped to RPC
  entrypoints.

  `TypeDiscovery.find_embedded_resources/1` used to hand bare resource modules
  to reachability, which then walked *all* public actions. An embedded resource
  referenced only by a public action that is never exposed through
  `typescript_rpc` leaked into the generated TypeScript — bloating the output
  and failing codegen for types clients can never reach. Discovery now passes
  `{resource, entrypoint_action_names}` so only exposed actions are traversed.

  The domain, resources and manifest are declared inline rather than added to
  `test/support` so the committed `test/ts` fixtures stay untouched.
  """

  # Mutates the global :manifest config, so must not run async.
  use ExUnit.Case, async: false

  alias AshTypescript.Codegen.TypeDiscovery

  defmodule ExposedEmbedded do
    use Ash.Resource, data_layer: :embedded, domain: nil, extensions: [AshTypescript.Resource]

    typescript do
      type_name "ExposedEmbedded"
    end

    attributes do
      uuid_primary_key :id
      attribute :label, :string, public?: true, allow_nil?: false
    end
  end

  defmodule UnexposedEmbedded do
    use Ash.Resource, data_layer: :embedded, domain: nil, extensions: [AshTypescript.Resource]

    typescript do
      type_name "UnexposedEmbedded"
    end

    attributes do
      uuid_primary_key :id
      attribute :label, :string, public?: true, allow_nil?: false
    end
  end

  defmodule Holder do
    use Ash.Resource,
      domain: AshTypescript.Codegen.EmbeddedEntrypointDiscoveryTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "EntrypointHolder"
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

      # Exposed via typescript_rpc below — its embedded return must be found.
      action :build_exposed, :struct do
        public? true

        constraints instance_of:
                      AshTypescript.Codegen.EmbeddedEntrypointDiscoveryTest.ExposedEmbedded

        run fn _input, _ctx ->
          {:ok, %AshTypescript.Codegen.EmbeddedEntrypointDiscoveryTest.ExposedEmbedded{}}
        end
      end

      # Public but NOT exposed via typescript_rpc — the only reference to
      # UnexposedEmbedded, which therefore must not be discovered.
      action :build_unexposed, :struct do
        public? true

        constraints instance_of:
                      AshTypescript.Codegen.EmbeddedEntrypointDiscoveryTest.UnexposedEmbedded

        run fn _input, _ctx ->
          {:ok, %AshTypescript.Codegen.EmbeddedEntrypointDiscoveryTest.UnexposedEmbedded{}}
        end
      end
    end
  end

  defmodule Domain do
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource AshTypescript.Codegen.EmbeddedEntrypointDiscoveryTest.Holder do
        rpc_action :list_entrypoint_holders, :read
        rpc_action :build_exposed, :build_exposed
      end
    end

    resources do
      resource AshTypescript.Codegen.EmbeddedEntrypointDiscoveryTest.Holder
    end
  end

  defmodule Manifest do
    use AshTypescript.Manifest,
      otp_app: :ash_typescript,
      domains: [AshTypescript.Codegen.EmbeddedEntrypointDiscoveryTest.Domain]
  end

  # Codegen resolves resources through `Ash.Info.domains/1`, so generation runs
  # against a dedicated otp_app to keep the shared test domains out of the way.
  @otp_app :embedded_entrypoint_discovery_test_app

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

    :ok
  end

  describe "find_embedded_resources/1" do
    test "finds embedded resources reachable through exposed rpc_action entrypoints" do
      assert ExposedEmbedded in TypeDiscovery.find_embedded_resources(@otp_app)
    end

    test "ignores embedded resources reachable only through unexposed public actions" do
      refute UnexposedEmbedded in TypeDiscovery.find_embedded_resources(@otp_app)
    end
  end

  describe "generated output" do
    setup do
      {:ok, files} = AshTypescript.Codegen.Orchestrator.generate(@otp_app, [])

      all_content = Enum.map_join(files, "\n", fn {_, content} -> content end)

      types_content =
        files
        |> Enum.filter(fn {path, _} -> String.ends_with?(path, "ash_types.ts") end)
        |> Enum.map_join("\n", fn {_, content} -> content end)

      refute types_content == "", "no types file was generated"

      %{types: types_content, all: all_content}
    end

    test "defines the schema for the embedded resource behind an entrypoint", %{types: types} do
      assert types =~ "export type ExposedEmbeddedResourceSchema = {"
    end

    test "emits nothing for the embedded resource behind an unexposed action", %{all: all} do
      refute all =~ "UnexposedEmbedded"
    end
  end
end
