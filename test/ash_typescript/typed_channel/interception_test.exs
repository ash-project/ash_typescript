# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.TypedChannel.WireItem do
  @moduledoc """
  Test resource whose publication payload has multi-word fields — the case
  where the wire format and the generated TypeScript types used to diverge
  (issue #79).
  """
  use Ash.Resource,
    domain: nil,
    notifiers: [Ash.Notifier.PubSub]

  pub_sub do
    module AshTypescript.Test.TestEndpoint
    prefix "wire"

    publish :create, [:id],
      event: "wire_item_created",
      public?: true,
      returns: :map,
      constraints: [
        fields: [
          id: [type: :uuid, allow_nil?: false],
          display_name: [type: :string, allow_nil?: true],
          created_at_ms: [type: :integer, allow_nil?: true]
        ]
      ],
      transform: fn notification ->
        %{id: notification.data.id, display_name: notification.data.name, created_at_ms: 0}
      end

    publish :update, [:id],
      event: "wire_item_touched",
      public?: true,
      returns: :integer,
      transform: fn _notification -> 1 end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  actions do
    defaults [:read, :create, :update]
  end
end

defmodule AshTypescript.Test.TypedChannel.WireChannel do
  @moduledoc false
  use Phoenix.Channel
  use AshTypescript.TypedChannel

  typed_channel do
    topic("wire:*")

    resource AshTypescript.Test.TypedChannel.WireItem do
      publish(:wire_item_created)
      publish(:wire_item_touched)
    end
  end

  @impl true
  def join("wire:" <> _suffix, _payload, socket), do: {:ok, socket}
end

defmodule AshTypescript.Test.TypedChannel.TypedChannelFirstChannel do
  @moduledoc false
  # `use AshTypescript.TypedChannel` before `use Phoenix.Channel`: our
  # before_compile hook runs first and Phoenix bakes the merged attribute.
  use AshTypescript.TypedChannel
  use Phoenix.Channel

  typed_channel do
    topic("wire_first:*")

    resource AshTypescript.Test.TypedChannel.WireItem do
      publish(:wire_item_created)
    end
  end

  @impl true
  def join(_topic, _payload, socket), do: {:ok, socket}
end

defmodule AshTypescript.Test.TypedChannel.CustomInterceptChannel do
  @moduledoc false
  # A channel with its own intercept + handle_out alongside the typed events.
  use Phoenix.Channel
  use AshTypescript.TypedChannel

  intercept(["custom_event"])

  typed_channel do
    topic("wire_custom:*")

    resource AshTypescript.Test.TypedChannel.WireItem do
      publish(:wire_item_created)
    end
  end

  @impl true
  def join(_topic, _payload, socket), do: {:ok, socket}

  @impl true
  def handle_out("custom_event", payload, socket) do
    push(socket, "custom_event", Map.put(payload, :handled_by_user, true))
    {:noreply, socket}
  end
end

defmodule AshTypescript.Test.TypedChannel.OwnHandleOutChannel do
  @moduledoc false
  # Declares two typed events but handles one of them itself — the injected
  # clause must step aside for `wire_item_created` and still cover the other.
  use Phoenix.Channel
  use AshTypescript.TypedChannel

  # Declaring the intercept explicitly is the documented workaround for the
  # Phoenix definition-time warning: Phoenix checks its intercept list when the
  # `handle_out/3` below is defined, which is before AshTypescript merges the
  # typed events in. Listing it twice is harmless.
  intercept(["wire_item_created"])

  typed_channel do
    topic("wire_own:*")

    resource AshTypescript.Test.TypedChannel.WireItem do
      publish(:wire_item_created)
      publish(:wire_item_touched)
    end
  end

  @impl true
  def join(_topic, _payload, socket), do: {:ok, socket}

  @impl true
  def handle_out("wire_item_created", payload, socket) do
    push(socket, "wire_item_created", Map.put(payload, :handled_by_user, true))
    {:noreply, socket}
  end
end

defmodule AshTypescript.TypedChannel.InterceptionTest do
  use ExUnit.Case, async: true

  @moduletag :ash_typescript

  alias AshTypescript.Test.TypedChannel.CustomInterceptChannel
  alias AshTypescript.Test.TypedChannel.OwnHandleOutChannel
  alias AshTypescript.Test.TypedChannel.TypedChannelFirstChannel
  alias AshTypescript.Test.TypedChannel.WireChannel
  alias AshTypescript.Test.TypedChannel.WireItem
  alias AshTypescript.TypedChannel.PayloadFormatter

  defmodule PassthroughSerializer do
    @moduledoc false
    def encode!(message), do: message
  end

  defp socket(topic) do
    %Phoenix.Socket{
      joined: true,
      transport_pid: self(),
      topic: topic,
      join_ref: "1",
      serializer: PassthroughSerializer
    }
  end

  describe "intercept injection" do
    test "declared events are intercepted (use Phoenix.Channel first)" do
      assert Enum.sort(WireChannel.__intercepts__()) ==
               ["wire_item_created", "wire_item_touched"]
    end

    test "declared events are intercepted (use AshTypescript.TypedChannel first)" do
      assert TypedChannelFirstChannel.__intercepts__() == ["wire_item_created"]
    end

    test "user-defined intercepts are preserved and merged" do
      assert Enum.sort(CustomInterceptChannel.__intercepts__()) ==
               ["custom_event", "wire_item_created"]
    end

    test "events handled by the developer stay in the intercept list" do
      assert Enum.sort(OwnHandleOutChannel.__intercepts__()) ==
               ["wire_item_created", "wire_item_touched"]
    end

    test "fixture channel with several resources intercepts all declared events" do
      assert Enum.sort(AshTypescript.Test.OrgChannel.__intercepts__()) ==
               ["item_created", "item_deleted", "item_updated"]
    end
  end

  describe "handle_out payload formatting" do
    test "multi-word payload fields reach the wire in output format" do
      payload = %{id: "abc-123", display_name: "Some Item", created_at_ms: 17}

      assert {:noreply, _socket} =
               WireChannel.handle_out("wire_item_created", payload, socket("wire:1"))

      assert_receive %Phoenix.Socket.Message{
        topic: "wire:1",
        event: "wire_item_created",
        payload: %{
          "id" => "abc-123",
          "displayName" => "Some Item",
          "createdAtMs" => 17
        }
      }
    end

    test "non-map payloads pass through unchanged" do
      assert {:noreply, _socket} =
               WireChannel.handle_out("wire_item_touched", 42, socket("wire:1"))

      assert_receive %Phoenix.Socket.Message{event: "wire_item_touched", payload: 42}
    end

    test "a developer clause for a typed event wins over the injected one" do
      assert {:noreply, _socket} =
               OwnHandleOutChannel.handle_out(
                 "wire_item_created",
                 %{display_name: "mine"},
                 socket("wire_own:1")
               )

      assert_receive %Phoenix.Socket.Message{
        event: "wire_item_created",
        payload: %{display_name: "mine", handled_by_user: true}
      }
    end

    test "typed events the developer does not handle still get injected clauses" do
      assert {:noreply, _socket} =
               OwnHandleOutChannel.handle_out("wire_item_touched", 7, socket("wire_own:1"))

      assert_receive %Phoenix.Socket.Message{event: "wire_item_touched", payload: 7}
    end

    test "user-defined handle_out clauses still run for their own events" do
      assert {:noreply, _socket} =
               CustomInterceptChannel.handle_out(
                 "custom_event",
                 %{some: "thing"},
                 socket("wire_custom:1")
               )

      assert_receive %Phoenix.Socket.Message{
        event: "custom_event",
        payload: %{some: "thing", handled_by_user: true}
      }
    end
  end

  describe "PayloadFormatter.format_payload/3" do
    test "formats map payloads according to the publication returns type" do
      assert PayloadFormatter.format_payload(WireItem, "wire_item_created", %{
               id: "x",
               display_name: "n",
               created_at_ms: 1
             }) == %{"id" => "x", "displayName" => "n", "createdAtMs" => 1}
    end

    test "passes payload through for events with no matching publication" do
      payload = %{display_name: "untouched"}
      assert PayloadFormatter.format_payload(WireItem, "unknown_event", payload) == payload
    end
  end

  describe "missing Phoenix.Channel warning" do
    test "warns when the module is not a Phoenix channel" do
      warning =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          defmodule NotAChannel do
            use AshTypescript.TypedChannel

            typed_channel do
              topic("not_a_channel:*")

              resource AshTypescript.Test.TypedChannel.WireItem do
                publish(:wire_item_created)
              end
            end
          end
        end)

      assert warning =~
               "AshTypescript.TypedChannel is being used in module " <>
                 "AshTypescript.TypedChannel.InterceptionTest.NotAChannel without " <>
                 "`use Phoenix.Channel`, you must add `use Phoenix.Channel` in order " <>
                 "for your typed channel to work as expected"
    end
  end
end
