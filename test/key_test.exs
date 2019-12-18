defmodule SlackDB.KeyTest do
  use ExUnit.Case

  import Mox
  import SlackDB.Key

  @get_all_replies [
    %{
      "text" => "1",
      "ts" => "12345",
      "reactions" => [%{"count" => 1}]
    },
    %{
      "text" => "2",
      "ts" => "12345",
      "reactions" => [%{"count" => 8}, %{"count" => 1}]
    },
    %{"text" => "3", "ts" => "12345"},
    %{"text" => "4", "ts" => "12345"}
  ]

  @pagination_result %{
    "has_more" => true,
    "messages" => [
      %{"text" => "key :family:", "ts" => "12345"},
      %{"text" => "3", "ts" => "12345"},
      %{"text" => "4", "ts" => "12345"}
    ],
    "ok" => true,
    "response_metadata" => %{"next_cursor" => "cursor1"}
  }

  setup do
    Messages.Mock
    |> expect(:get_all_replies, 3, fn
      _ -> {:ok, @get_all_replies}
    end)

    Client.Mock
    |> expect(:conversations_replies, 1, fn
      _, _, _ -> {:ok, @pagination_result}
    end)

    :ok
  end

  test "votable key" do
    assert get_value(%SlackDB.Key{
             channel_id: "CFFD4EEMR",
             channel_name: "general",
             key_phrase: "key",
             metadata: [:voting],
             server_name: "server",
             ts: "1555913457.017900"
           }) === {:ok, "2"}
  end

  test "multiple key" do
    assert get_value(%SlackDB.Key{
             channel_id: "CFFD4EEMR",
             channel_name: "general",
             key_phrase: "key",
             metadata: [:multiple],
             server_name: "server",
             ts: "1555913457.017900"
           }) === {:ok, ["1", "2", "3", "4"]}
  end

  test "single front key" do
    assert get_value(%SlackDB.Key{
             channel_id: "CFFD4EEMR",
             channel_name: "general",
             key_phrase: "key",
             metadata: [:single_front],
             server_name: "server",
             ts: "1555913457.017900"
           }) === {:ok, "1"}
  end

  test "single back key" do
    assert get_value(%SlackDB.Key{
             channel_id: "CFFD4EEMR",
             channel_name: "general",
             key_phrase: "key",
             metadata: [:single_back],
             server_name: "server",
             ts: "1555913457.017900"
           }) === {:ok, "4"}
  end
end
