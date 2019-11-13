defmodule StatelessTest do
  use ExUnit.Case
  # doctest SlackDB
  import SlackDB

  test "put_kv_in" do
    map1 = %{top: %{middle: %{}}}

    map2 = SlackDB.Utils.put_kv_in(map1, [:top, :middle], :bottom, "hi")

    assert map2 === %{top: %{middle: %{bottom: "hi"}}}
  end

  test "populate_channels" do
    servers = %{"server1" => %{}, "server2" => %{}}
    server_states = [{"server1", %{"channel1" => "id"}}, {"server2", %{"channel1" => "id"}}]

    assert populate_channels(servers, server_states) === %{
             "server1" => %{channels: %{"channel1" => "id"}},
             "server2" => %{channels: %{"channel1" => "id"}}
           }
  end

  test "parse_matches and first_matched_schema" do
    assert SlackDB.Search.parse_matches(%{"total" => 0, "matches" => []}) ===
             {:error, "no_search_matches"}

    assert SlackDB.Search.parse_matches(%{
             "total" => 3,
             "matches" => [
               %{"text" => "keydoesntmatch:emoji:"}
             ]
           }) === {:error, "no_search_result_matching_key_schema"}

    assert SlackDB.Search.parse_matches(%{
             "total" => 3,
             "matches" => [
               %{"text" => "keydoesntmatch:emoji:"},
               %{
                 "text" =>
                   "any.characters|followed/by*space :monkey::anchor: ,asdfj :do_not_litter: ",
                 "channel" => %{"id" => "channel_id", "name" => "channel_name"},
                 "ts" => "ts"
               }
             ]
           }) ===
             {:ok,
              %SlackDB.Key{
                key_phrase: "any.characters|followed/by*space",
                metadata: [:single_back, :undeletable, :constant],
                channel_id: "channel_id",
                channel_name: "channel_name",
                ts: "ts",
                server_name: nil
              }}
  end

  test "tally_reactions" do
    assert SlackDB.Key.tally_reactions(%{"blah" => false}) === 0

    assert SlackDB.Key.tally_reactions(%{
             "reactions" => [
               %{"count" => 1},
               %{"count" => 4}
             ]
           }) === 5
  end
end
