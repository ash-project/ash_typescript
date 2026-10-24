# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedChannel.PayloadTypeAliasesTest do
  @moduledoc """
  Typed channel payload types are appended to `ash_types.ts` and reference
  type aliases (`Duration`, `AshDate`, ...). Those aliases must be declared
  even when no RPC resource uses the type: here the only RPC resource has a
  UUID primary key and nothing else.
  """

  # Mutates the global :manifest / :typed_channels config, so must not run async.
  use ExUnit.Case, async: false

  @moduletag :ash_typescript

  defmodule Plain do
    use Ash.Resource,
      domain: AshTypescript.TypedChannel.PayloadTypeAliasesTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "PlainRecord"
    end

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
    end

    actions do
      defaults [:read]
    end
  end

  defmodule Domain do
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource AshTypescript.TypedChannel.PayloadTypeAliasesTest.Plain do
        rpc_action :list_plain_records, :read
      end
    end

    resources do
      resource AshTypescript.TypedChannel.PayloadTypeAliasesTest.Plain
    end
  end

  defmodule Manifest do
    use AshTypescript.Manifest,
      otp_app: :ash_typescript,
      domains: [AshTypescript.TypedChannel.PayloadTypeAliasesTest.Domain]
  end

  defmodule Job do
    use Ash.Resource, domain: nil, notifiers: [Ash.Notifier.PubSub]

    pub_sub do
      module AshTypescript.Test.TestEndpoint
      prefix "alias_jobs"

      publish :create, [:id],
        event: "alias_job_finished",
        public?: true,
        returns: :map,
        constraints: [
          fields: [
            elapsed: [type: :duration],
            on: [type: :date],
            outcome: [
              type: :union,
              constraints: [types: [failed_at: [type: :naive_datetime], note: [type: :string]]]
            ]
          ]
        ],
        transform: fn _notification -> %{} end
    end

    attributes do
      uuid_primary_key :id
    end

    actions do
      defaults [:create]
    end
  end

  defmodule JobChannel do
    use Phoenix.Channel
    use AshTypescript.TypedChannel

    def join(_topic, _payload, socket), do: {:ok, socket}

    typed_channel do
      topic "alias_jobs:*"

      resource AshTypescript.TypedChannel.PayloadTypeAliasesTest.Job do
        publish(:alias_job_finished)
      end
    end
  end

  @otp_app :payload_type_aliases_test_app

  setup_all do
    AshTypescript.Test.TestHelpers.restore_application_env_on_exit([
      :manifest,
      :typed_controllers,
      :typed_channels
    ])

    AshTypescript.Test.TestHelpers.restore_application_env_on_exit([:ash_domains], @otp_app)

    Application.put_env(:ash_typescript, :manifest, Manifest)
    Application.put_env(:ash_typescript, :typed_controllers, [])
    Application.put_env(:ash_typescript, :typed_channels, [JobChannel])
    Application.put_env(@otp_app, :ash_domains, [Domain])

    {:ok, files} = AshTypescript.Codegen.Orchestrator.generate(@otp_app, [])

    types =
      files
      |> Enum.filter(fn {path, _} -> String.ends_with?(path, "ash_types.ts") end)
      |> Enum.map_join("\n", fn {_, content} -> content end)

    refute types == "", "no types file was generated"

    %{types: types}
  end

  for alias_name <- ["Duration", "AshDate", "NaiveDateTime"] do
    test "declares #{alias_name} used only in a typed channel payload", %{types: types} do
      alias_name = unquote(alias_name)

      [payload] = Regex.run(~r/export type AliasJobFinishedPayload = .*;/, types)
      assert payload =~ ~r/\b#{alias_name}\b/, "expected the payload to reference #{alias_name}"

      assert types =~ "export type #{alias_name} = string;"
    end
  end
end
