# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.CustomTypeOutput.Item do
  @moduledoc """
  A publication whose payload holds a built-in declared custom type (Money),
  a TypedStruct and a typed map, each carrying keys their types don't declare.
  """
  use Ash.Resource,
    domain: nil,
    notifiers: [Ash.Notifier.PubSub]

  pub_sub do
    module AshTypescript.Test.TestEndpoint
    prefix "custom_output"

    publish :create, [:id],
      event: "custom_output_created",
      public?: true,
      returns: :map,
      constraints: [
        fields: [
          price: [type: AshMoney.Types.Money],
          stats: [type: AshTypescript.Test.TaskStats],
          summary: [
            type: :map,
            constraints: [fields: [total_count: [type: :integer]]]
          ]
        ]
      ],
      transform: fn _notification -> AshTypescript.CustomTypeOutputTest.payload() end
  end

  attributes do
    uuid_primary_key :id
  end

  actions do
    defaults [:read, :create]
  end
end

defmodule AshTypescript.Test.CustomTypeOutput.Channel do
  @moduledoc false
  use Phoenix.Channel
  use AshTypescript.TypedChannel

  typed_channel do
    topic "custom_output:*"

    resource AshTypescript.Test.CustomTypeOutput.Item do
      publish :custom_output_created
    end
  end

  @impl true
  def join(_topic, _payload, socket), do: {:ok, socket}
end

defmodule AshTypescript.Test.CustomTypeOutput.Session do
  @moduledoc false
  use AshTypescript.TypedController

  typed_controller do
    module_name AshTypescript.Test.CustomTypeOutput.Controller

    post :reply do
      returns :map

      constraints fields: [
                    price: [type: AshMoney.Types.Money],
                    stats: [type: AshTypescript.Test.TaskStats],
                    summary: [
                      type: :map,
                      constraints: [fields: [total_count: [type: :integer]]]
                    ]
                  ]

      run fn conn, _params ->
        AshTypescript.TypedController.json(conn, AshTypescript.CustomTypeOutputTest.payload())
      end
    end
  end
end

defmodule AshTypescript.CustomTypeOutputTest do
  # Guards: typed maps and structs (declared custom types included) send only
  # their declared fields on paths without field selection, and struct values
  # format instead of raising. ash_rpc does this since declared-only output.
  use ExUnit.Case, async: false

  @moduletag :ash_typescript

  alias AshTypescript.Codegen.TypeMapper
  alias AshTypescript.Test.CustomTypeOutput.{Channel, Item, Session}
  alias AshTypescript.TypedChannel.PayloadFormatter
  alias AshTypescript.TypedController.RequestHandler

  @expected %{
    "price" => %{"currency" => "USD", "amount" => "10.50"},
    "stats" => %{
      "totalCount" => 3,
      "completed" => true,
      "isUrgent" => false,
      "averageDuration" => nil
    },
    "summary" => %{"totalCount" => 2}
  }

  @doc false
  def payload do
    %{
      # A Money-like value with a key Money doesn't declare.
      price: %{
        currency: "USD",
        amount: Decimal.new("10.50"),
        format_options: [fractional_digits: 2]
      },
      # A struct value (a TypedStruct) carrying a key its fields don't declare.
      stats:
        Map.put(
          %AshTypescript.Test.TaskStats{total_count: 3, completed?: true},
          :internal,
          "secret"
        ),
      summary: %{total_count: 2, internal: "secret"}
    }
  end

  defp manifest do
    AshTypescript.Test.InlineManifest.build!(
      typed_controllers: [Session],
      typed_channels: [Channel]
    )
  end

  describe "generated TypeScript" do
    # The route result and channel payload types codegen emits: Money is an
    # object of its declared fields, not an alias or a record.
    test "a route result types a declared custom type by its fields" do
      route = AshTypescript.Manifest.Custom.route(manifest(), Session, :reply)

      result =
        AshTypescript.with_manifest(manifest(), fn ->
          TypeMapper.map_route_result_type(route.returns)
        end)

      assert result =~ ~r/price\??: \{currency: string, amount: Decimal\}/
      refute result =~ "Money"
    end

    test "a channel payload types a declared custom type by its fields" do
      publication =
        AshTypescript.Manifest.Custom.publication(
          manifest(),
          Channel,
          Item,
          "custom_output_created"
        )

      payload =
        AshTypescript.with_manifest(manifest(), fn ->
          TypeMapper.map_channel_payload_type(publication.returns)
        end)

      # A pushed payload has no field selection: nested typed containers are
      # plain objects too, without the TypedMap metadata, as in route results.
      assert payload =~ ~r/price\??: \{currency: string, amount: Decimal\}/
      refute payload =~ "__type"
      refute payload =~ "Money"

      assert AshTypescript.with_manifest(manifest(), fn ->
               TypeMapper.map_channel_payload_type(%Ash.Info.Manifest.Type{
                 kind: :type_ref,
                 module: AshMoney.Types.Money
               })
             end) == "{currency: string, amount: Decimal}"
    end
  end

  test "a typed route result sends declared fields only" do
    conn = Plug.Test.conn(:post, "/test", %{})

    conn =
      AshTypescript.with_manifest(manifest(), fn ->
        RequestHandler.handle(conn, Session, :reply, %{})
      end)

    assert conn.status == 200, conn.resp_body
    assert Jason.decode!(conn.resp_body) == @expected
  end

  test "a typed channel payload sends declared fields only" do
    formatted =
      AshTypescript.with_manifest(manifest(), fn ->
        PayloadFormatter.format_payload(Channel, Item, "custom_output_created", payload())
      end)

    assert formatted |> Jason.encode!() |> Jason.decode!() == @expected
  end
end
