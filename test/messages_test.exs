defmodule SlackDB.MessagesTest do
  use ExUnit.Case, async: false

  import Mox
  import SlackDB.Messages

  @post_message_result %{
    "channel" => "CQGTEPMUL",
    "message" => %{
      "text" => "hello",
      "thread_ts" => "1573678209.000700",
      "ts" => "1576181323.002500",
      "type" => "message",
      "user" => "UQGHG5JF6"
    },
    "ok" => true,
    "ts" => "1576181323.002500"
  }

  @delete_message_result %{"channel" => "CQ5H0JBDZ", "ok" => true, "ts" => "1576183476.000200"}

  @pagination_result_1 %{
    "has_more" => true,
    "messages" => [
      %{"text" => "key :family:", "ts" => "12345"},
      %{"text" => "3", "ts" => "12345"},
      %{"text" => "4", "ts" => "12345"}
    ],
    "ok" => true,
    "response_metadata" => %{"next_cursor" => "cursor1"}
  }

  @pagination_result_2 %{
    "has_more" => false,
    "messages" => [
      %{"text" => "key :family:", "ts" => "12345"},
      %{"text" => "1", "ts" => "12345"},
      %{"text" => "2", "ts" => "12345"}
    ],
    "ok" => true
  }

  setup do
    Client.Mock
    |> expect(:conversations_replies, 6, fn
      _, _, cursor: nil -> {:ok, @pagination_result_1}
      _, _, cursor: "cursor1" -> {:ok, @pagination_result_2}
    end)
    |> expect(:chat_postMessage, 2, fn
      _, _, _, _ -> {:ok, @post_message_result}
    end)
    |> expect(:chat_delete, 9, fn
      _, _, _ -> {:ok, @delete_message_result}
    end)

    :ok
  end

  setup :set_mox_global

  test "post_thread" do
    key = %{server_name: "server", ts: "ts", channel_id: "id"}

    assert post_thread(key, "hello") == {:ok, [ok: @post_message_result]}

    assert key
           |> Map.put(:server_name, "not_found")
           |> post_thread("hello") ===
             {:error, "KeyError: couldn't find key `not_found`"}
  end

  test "wipe_thread" do
    key = %{server_name: "server", ts: "ts", channel_id: "id"}

    assert wipe_thread(key, include_key?: false) ===
             {:ok, List.duplicate({:ok, @delete_message_result}, 4)}

    assert wipe_thread(key) ===
             {:ok, List.duplicate({:ok, @delete_message_result}, 5)}

    assert key
           |> Map.put(:server_name, "not_found")
           |> wipe_thread() ===
             {:error, "KeyError: couldn't find key `not_found`"}
  end

  test "conversations_replies" do
    key = %{server_name: "server"}

    assert get_all_replies(key) ===
             {:ok,
              [
                %{"text" => "1", "ts" => "12345"},
                %{"text" => "2", "ts" => "12345"},
                %{"text" => "3", "ts" => "12345"},
                %{"text" => "4", "ts" => "12345"}
              ]}

    assert key
           |> Map.put(:server_name, "not_found")
           |> get_all_replies() ===
             {:error, "KeyError: couldn't find key `not_found`"}
  end
end
