# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.TypedChannel.EncoderHiddenCredentials do
  @moduledoc """
  A non-scalar struct whose `Jason.Encoder` hides a field. Under a `:term`
  position the formatter must leave it to its encoder.
  """
  @derive {Jason.Encoder, only: [:public_part]}
  defstruct [:public_part, :password]
end

defmodule AshTypescript.Test.TypedChannel.ObjectKindsItem do
  @moduledoc """
  Publications for the plain-data payload kinds a typed channel accepts,
  pushed through Phoenix's JSON serializer in the tests below.
  """
  use Ash.Resource,
    domain: nil,
    notifiers: [Ash.Notifier.PubSub]

  pub_sub do
    module AshTypescript.Test.TestEndpoint
    prefix "object_kinds"

    publish :create, [:id],
      event: "as_keyword",
      public?: true,
      returns: :keyword,
      constraints: [fields: [item_count: [type: :integer]]],
      transform: fn _notification -> nil end

    publish :create, [:id],
      event: "as_tuple",
      public?: true,
      returns: :tuple,
      constraints: [fields: [item_count: [type: :integer], label: [type: :string]]],
      transform: fn _notification -> nil end

    publish :create, [:id],
      event: "as_typed_struct",
      public?: true,
      returns: :struct,
      constraints: [fields: [item_count: [type: :integer]]],
      transform: fn _notification -> nil end

    publish :create, [:id],
      event: "as_map_new_type",
      public?: true,
      returns: AshTypescript.Test.CustomMetadata,
      transform: fn _notification -> nil end

    publish :create, [:id],
      event: "scalar_structs",
      public?: true,
      returns: :map,
      constraints: [fields: [took: [type: :duration], on: [type: :date]]],
      transform: fn _notification -> nil end

    publish :create, [:id],
      event: "term_values",
      public?: true,
      returns: :map,
      constraints: [fields: [credentials: [type: :term], took: [type: :term]]],
      transform: fn _notification -> nil end
  end

  attributes do
    uuid_primary_key :id
  end

  actions do
    defaults [:read, :create]
  end
end

defmodule AshTypescript.Test.TypedChannel.ObjectKindsChannel do
  @moduledoc false
  use Phoenix.Channel
  use AshTypescript.TypedChannel

  typed_channel do
    topic "object_kinds:*"

    resource AshTypescript.Test.TypedChannel.ObjectKindsItem do
      publish :as_keyword
      publish :as_tuple
      publish :as_typed_struct
      publish :as_map_new_type
      publish :scalar_structs
      publish :term_values
    end
  end

  @impl true
  def join(_topic, _payload, socket), do: {:ok, socket}
end

defmodule AshTypescript.TypedChannel.PayloadFormatterTest do
  use ExUnit.Case, async: true

  @moduletag :ash_typescript

  alias AshTypescript.Test.TypedChannel.EncoderHiddenCredentials
  alias AshTypescript.Test.TypedChannel.ObjectKindsChannel
  alias AshTypescript.Test.TypedChannel.ObjectKindsItem
  alias AshTypescript.TypedChannel.PayloadFormatter

  # The test-local channel is in no manifest module option (that would change
  # the generated snapshots), so it is formatted through an inline manifest.
  defp manifest do
    AshTypescript.Test.InlineManifest.build!(
      typed_controllers: [],
      typed_channels: [ObjectKindsChannel]
    )
  end

  defp format(event, payload) do
    AshTypescript.with_manifest(manifest(), fn ->
      PayloadFormatter.format_payload(ObjectKindsChannel, ObjectKindsItem, event, payload)
    end)
  end

  defp json_socket do
    %Phoenix.Socket{
      joined: true,
      transport_pid: self(),
      topic: "object_kinds:1",
      join_ref: "1",
      serializer: Phoenix.Socket.V2.JSONSerializer
    }
  end

  defp push(event, payload) do
    AshTypescript.with_manifest(manifest(), fn ->
      PayloadFormatter.push_formatted(
        json_socket(),
        ObjectKindsChannel,
        ObjectKindsItem,
        event,
        payload
      )
    end)
  end

  defp pushed_payload do
    assert_receive {:socket_push, :text, json}
    json |> IO.iodata_to_binary() |> Jason.decode!() |> List.last()
  end

  describe "typed scalar structs" do
    test "are normalized at typed positions" do
      assert format("scalar_structs", %{took: Duration.new!(hour: 1), on: ~D[2026-01-15]}) ==
               %{"took" => "PT1H", "on" => "2026-01-15"}
    end
  end

  describe ":term values" do
    # Untyped data is sent as produced: neither struct is normalized.
    test "structs are returned untouched" do
      credentials = %EncoderHiddenCredentials{public_part: "visible", password: "hunter2"}
      took = Duration.new!(hour: 1)

      assert format("term_values", %{credentials: credentials, took: took}) ==
               %{"credentials" => credentials, "took" => took}
    end
  end

  describe "push_formatted/5 through Phoenix's JSON serializer" do
    test "keyword, tuple, struct and map NewType payloads encode as JSON objects" do
      :ok = push("as_keyword", item_count: 2)
      assert pushed_payload() == %{"itemCount" => 2}

      :ok = push("as_tuple", {2, "two"})
      assert pushed_payload() == %{"itemCount" => 2, "label" => "two"}

      :ok = push("as_typed_struct", %{item_count: 4})
      assert pushed_payload() == %{"itemCount" => 4}

      :ok = push("as_map_new_type", %{field_1: "a", is_active?: true, line_2: nil})
      assert pushed_payload() == %{"field1" => "a", "isActive" => true, "line2" => nil}
    end

    test "a struct under :term encodes through its own Jason.Encoder" do
      :ok =
        push("term_values", %{
          credentials: %EncoderHiddenCredentials{public_part: "visible", password: "hunter2"}
        })

      assert_receive {:socket_push, :text, json}
      json = IO.iodata_to_binary(json)

      refute json =~ "hunter2"

      assert json |> Jason.decode!() |> List.last() == %{
               "credentials" => %{"public_part" => "visible"}
             }
    end
  end
end
