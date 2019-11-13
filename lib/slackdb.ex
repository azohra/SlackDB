defmodule SlackDB do
  @moduledoc """
  GenServer that is responsible for all interactions with SlackDB.

  On startup, the server will load into memory the current state of the
  server (as described in the supervisor channel). All changes to state
  (channel additions and archivals) made through this API will be updated
  and persisted in the supervisor channel
  """
  use GenServer
  use Private
  require Logger
  alias SlackDB.Client
  alias SlackDB.Utils
  alias SlackDB.Messages
  alias SlackDB.Search
  alias SlackDB.Key
  alias SlackDB.Channels

  # @typedoc """
  # Types of SlackDB keys represented as atoms

  # Types
  #   * `:voting` - replies to keys are treated as a ballot where reactions represent support for that particular value. winner takes all.
  #   * `:multiple` - the reply thread represents an array that is returned in full and in chronological order
  #   * `:single_front` - the first reply to the key is the value
  #   * `:single_back` - the most recent reply to the key is the value
  # """
  # @type key_type :: :voting | :multiple | :single_front | :single_back

  # @typedoc """
  # More key metadata options represented as atoms

  # Types
  #   * `:constant` - key cannot changed after creation (save for deletion)
  #   * `:undeletable` - key cannot be deleted (through this API)
  # """
  # @type more_metadata :: :constant | :undeletable

  @typedoc """
  Represents the types of values that keys can hold. Since all values are stored in Slack,
  they are all returned as strings (or a list of strings in the case of key_type `:multiple`)
  """
  @type value :: String.t() | list(String.t())

  @metadata_to_emoji %{
    voting: ":thumbsup:",
    multiple: ":family:",
    single_front: ":hear_no_evil:",
    single_back: ":monkey:",
    constant: ":do_not_litter:",
    undeletable: ":anchor:"
    # locked: ":octagonal_sign:",
  }
  ####################################################################################
  ## PUBLIC API ######################################################################
  ####################################################################################

  @doc """
  Start genserver, pull server config from application environment and pass to init/1
  """
  def start_link do
    config = Application.get_env(:slackdb, :servers)

    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Create a key/value pair in the specified server and channel of the given type

  This essentially overwrites the key if it already exist. It posts a new message that will always be prioritized by `read/4` because it is more recent.

  The value passed in may be either a String or a list of Strings that will be posted in the key's thread, in order.
  You can specify additional metadata to be added to the key using an optional list.

  This function returns an error tuple or a list of tuples indicating the result of posting each value.
  The channel that is specified must exist in the scope of the server.

  ## Example

      iex> SlackDB.create("dog_shelter", "adopted", "Beagles", ["Buddy", "Rufus"], :multiple, [:undeletable])
      [
        ok: %{
          "channel" => "CHU427918",
          "message" => %{...},
          "ok" => true,
          "ts" => "1556129092.000800"
        },
        ok: %{
          "channel" => "CHU427918",
          "message" => %{...},
          "ok" => true,
          "ts" => "1556129093.001000"
        }
      ]
  """
  @spec create(
          String.t(),
          String.t(),
          String.t(),
          value(),
          SlackDB.Key.type(),
          list(SlackDB.Key.more_metadata())
        ) :: {:error, String.t()} | list(tuple())
  def create(server_name, channel_name, key_phrase, value, key_type, add_metadata \\ [])

  def create(server_name, channel_name, key_phrase, value, key_type, add_metadata)
      when is_binary(value) and is_list(add_metadata) and is_atom(key_type),
      do: create(server_name, channel_name, key_phrase, [value], key_type, add_metadata)

  def create(server_name, channel_name, key_phrase, values, key_type, add_metadata)
      when is_list(values) and is_list(add_metadata) and is_atom(key_type) do
    Utils.check_schema(key_phrase)
    |> case do
      nil ->
        GenServer.call(
          __MODULE__,
          {:create, server_name, channel_name, key_phrase, values, [key_type | add_metadata]}
        )

      _ ->
        {:error, "invalid_key_phrase"}
    end
  end

  @doc """
  Reads a key in the given server and channel, raising an error if anything went wrong

  This will always pull from the most recently posted message that matches the key schema.

  Setting `only_bot?` to true will search only for keys posted under the bot name specified in the config.

  ## Example

      iex> SlackDB.read!("dog_shelter", "adopted", "Beagles")
      ["Buddy", "Rufus"]
  """
  @spec read!(String.t(), String.t(), String.t(), boolean()) :: value()
  def read!(server_name, channel_name, key_phrase, only_bot? \\ true) do
    read(server_name, channel_name, key_phrase, only_bot?)
    |> case do
      {:ok, val} -> val
      {:error, msg} -> raise msg
    end
  end

  @doc """
  Reads a key in the given server and channel

  This will always pull from the most recently posted message that matches the key schema.

  Setting `only_bot?` to true will search only for keys posted under the bot name specified in the config.

  ## Example

      iex> SlackDB.read("dog_shelter", "adopted", "Beagles")
      {:ok, ["Buddy", "Rufus"]}
  """
  @spec read(String.t(), String.t(), String.t(), boolean()) ::
          {:error, String.t()} | {:ok, value()}
  def read(server_name, channel_name, key_phrase, only_bot? \\ true) do
    with {:ok, key} <- Search.search(server_name, channel_name, key_phrase, only_bot?) do
      # IO.inspect(key)
      Key.get_value(key)
    else
      err -> err
    end
  end

  @doc """
  Overwrites the current value of the key by deleting the current thread and posting new values (sacrificing rollback)

  This is the only way to change the value of a `:single_front` key.

  This function returns an error tuple or a list of tuples indicating the result of posting each value.

  ## Example

      iex> SlackDB.update("dog_shelter", "adopted", "Chihuahuas", "Ren")
      [
        ok: %{
          "channel" => "CHU427918",
          "message" => %{...},
          "ok" => true,
          "ts" => "1556129092.000800"
        },
      ]
  """
  @spec update(String.t(), String.t(), String.t(), value()) ::
          {:error, String.t()} | list(tuple())
  def update(server_name, channel_name, key_phrase, value) when is_binary(value),
    do: update(server_name, channel_name, key_phrase, [value])

  def update(server_name, channel_name, key_phrase, values) when is_list(values) do
    with %{bot_token: bot_token, user_token: user_token} <-
           Application.get_env(:slackdb, :servers) |> Map.get(server_name),
         {:ok, key} <- Search.search(server_name, channel_name, key_phrase, false) do
      cond do
        :constant in key.metadata ->
          {:error, "cannot_update_constant_key"}

        true ->
          Messages.wipe_thread(user_token, key, false)
          Messages.post_thread(bot_token, key.channel_id, values, key.ts)
      end
    else
      nil -> {:error, "server_not_found_in_config"}
      %{} -> {:error, "improper_config"}
      err -> err
    end
  end

  @doc """
  Deletes a key and it's associated thread

  Beware of rate_limiting issues discussed in the README

  This function returns an error tuple or a list of tuples indicating the result of deleting each message in the thread.

  ## Example

      iex> SlackDB.delete("dog_shelter", "yet-to-be-adopted", "Chihuahuas")
      [
        ok: %{
          "channel" => "CHU427918",
          "message" => %{...},
          "ok" => true,
          "ts" => "1556129092.000800"
        },
      ]
  """
  @spec delete(String.t(), String.t(), String.t()) :: {:error, String.t()} | list(tuple())
  def delete(server_name, channel_name, key_phrase) do
    with %{user_token: user_token} <-
           Application.get_env(:slackdb, :servers) |> Map.get(server_name),
         {:ok, key} <- Search.search(server_name, channel_name, key_phrase, false) do
      cond do
        :undeletable in key.metadata -> {:error, "cannot_delete_undeletable_key"}
        true -> Messages.wipe_thread(user_token, key, true)
      end
    else
      nil -> {:error, "server_not_found_in_config"}
      %{} -> {:error, "improper_config"}
      err -> err
    end
  end

  @doc """
  Appends values to the current thread of the key (maintaining history)

  You can use this to append to the list of keys with type `:multiple`.
  Or to add voting options to `:voting` keys.
  Or to change the value of `:single_back` keys

  This function returns an error tuple or a list of tuples indicating the result of posting each value.

  ## Example

      iex> SlackDB.append("dog_shelter", "adopted", "Chihuahuas", "Ren")
      [
        ok: %{
          "channel" => "CHU427918",
          "message" => %{...},
          "ok" => true,
          "ts" => "1556129092.000800"
        }
      ]
  """
  @spec append(String.t(), String.t(), String.t(), value()) ::
          {:error, String.t()} | list(tuple())
  def append(server_name, channel_name, key_phrase, value) when is_binary(value),
    do: append(server_name, channel_name, key_phrase, [value])

  def append(server_name, channel_name, key_phrase, values) when is_list(values) do
    with %{bot_token: bot_token} <-
           Application.get_env(:slackdb, :servers) |> Map.get(server_name),
         {:ok, key} <- Search.search(server_name, channel_name, key_phrase, true) do
      cond do
        :constant in key.metadata ->
          {:error, "cannot_append_to_constant_key"}

        true ->
          Messages.post_thread(bot_token, key.channel_id, values, key.ts)
      end
    else
      nil -> {:error, "server_not_found_in_config"}
      %{} -> {:error, "improper_config"}
      err -> err
    end
  end

  @doc """
  Creates a new channel and updates the current state of the database

  A channel must exist in the current state of the databse to create keys or to invite users.
  Since bots cannot add themselves to channels, you must also add the bot manually once the channel is created.

  ## Example

      iex> SlackDB.new_channel("dog_shelter", "volunteers", false)
      {:ok, "channel added"}
  """
  @spec new_channel(String.t(), String.t(), boolean()) :: {:error, String.t()} | {:ok, map()}
  def new_channel(server_name, channel_name, is_private?) do
    with %{user_token: user_token, supervisor_channel_name: supervisor_channel_name} <-
           Application.get_env(:slackdb, :servers) |> Map.get(server_name),
         {:ok, %{"name" => channel_name, "id" => channel_id}} <-
           Client.conversations_create(user_token, channel_name, is_private?),
         {:ok, new_state} <-
           GenServer.call(__MODULE__, {:put_channel, server_name, channel_name, channel_id}),
         [{:ok, _resp}] <-
           append(
             server_name,
             supervisor_channel_name,
             server_name,
             new_state |> get_in([server_name, :channels]) |> Jason.encode!()
           ) do
      {:ok, new_state}
    else
      nil -> {:error, "server_not_found_in_config"}
      %{} -> {:error, "improper_config"}
      err -> err
    end
  end

  @doc """
  Includes an existing channel and updates the state of the database

  A channel must exist in the current state of the databse to create keys or to invite users
  Since bots cannot add themselves to channels, you must also add the bot manually once the channel is included.

  ## Example

      iex> SlackDB.include_channel("dog_shelter", "employees")
      {:ok, "channel added"}
  """
  @spec include_channel(String.t(), String.t()) :: {:error, String.t()} | {:ok, map()}
  def include_channel(server_name, channel_name) do
    with %{user_token: user_token, supervisor_channel_name: supervisor_channel_name} <-
           Application.get_env(:slackdb, :servers) |> Map.get(server_name),
         {:ok, resp} <- Client.conversations_list(user_token),
         convo_list <- Channels.get_all_convos(user_token, [], resp) do
      case convo_list |> Enum.find(fn chnl -> chnl["name"] == channel_name end) do
        nil ->
          {:error, "channel_not_found"}

        %{"id" => channel_id} ->
          with {:ok, new_state} <-
                 GenServer.call(__MODULE__, {:put_channel, server_name, channel_name, channel_id}),
               [{:ok, _resp}] <-
                 append(
                   server_name,
                   supervisor_channel_name,
                   server_name,
                   new_state |> get_in([server_name, :channels]) |> Jason.encode!()
                 ) do
            {:ok, new_state}
          else
            err -> err
          end
      end
    else
      nil -> {:error, "server_not_found_in_config"}
      %{} -> {:error, "improper_config"}
      err -> err
    end
  end

  @doc """
  Archives a channel and removes it from the state of the database

  ## Example

      iex> SlackDB.archive_channel("dog_shelter", "coops-winter-2019")
      {:ok, "channel archived"}
  """
  @spec archive_channel(String.t(), String.t()) :: {:error, String.t()} | {:ok, map()}
  def archive_channel(server_name, channel_name) do
    with %{supervisor_channel_name: supervisor_channel_name} <-
           Application.get_env(:slackdb, :servers) |> Map.get(server_name),
         {:ok, _resp} <- GenServer.call(__MODULE__, {:archive, server_name, channel_name}),
         new_state <- GenServer.call(__MODULE__, {:dump}),
         [{:ok, _resp}] <-
           append(
             server_name,
             supervisor_channel_name,
             server_name,
             new_state |> get_in([server_name, :channels]) |> Jason.encode!()
           ) do
      {:ok, new_state}
    else
      nil -> {:error, "server_not_found_in_config"}
      %{} -> {:error, "improper_config"}
      err -> err
    end
  end

  @doc """
  Invites a user_id or a list of user_ids to a specified channel

  ## Example

      iex> SlackDB.invite_to_channel("dog_shelter", "adopted", ["USERID1", "USERID2"])
      {:ok, %{"name" => "adopted", "id" => "CHU427918"}}
  """
  @spec invite_to_channel(String.t(), String.t(), String.t() | list(String.t())) ::
          {:error, String.t()} | {:ok, map()}
  def invite_to_channel(server_name, channel_name, user_id) when is_binary(user_id),
    do: invite_to_channel(server_name, channel_name, [user_id])

  def invite_to_channel(server_name, channel_name, user_ids)
      when is_list(user_ids) and length(user_ids) < 30 and length(user_ids) > 0 do
    GenServer.call(__MODULE__, {:invite, server_name, channel_name, user_ids})
  end

  @doc """
  Invites a user_id or a list of user_ids to the supervisor channel of a specified server

  ## Example

      iex> SlackDB.invite_supervisors("dog_shelter", ["USERID1", "USERID2"])
      {:ok, %{"name" => "adopted", "id" => "CHU427918"}}
  """
  @spec invite_supervisors(String.t(), String.t() | list(String.t())) ::
          {:error, String.t()} | {:ok, map()}
  def invite_supervisors(server_name, user_id) when is_binary(user_id),
    do: invite_supervisors(server_name, [user_id])

  def invite_supervisors(server_name, user_ids)
      when is_list(user_ids) and length(user_ids) < 30 and length(user_ids) > 0 do
    with %{user_token: user_token, supervisor_channel_id: supervisor_channel_id} <-
           Application.get_env(:slackdb, :servers) |> Map.get(server_name) do
      Client.conversations_invite(
        user_token,
        supervisor_channel_id,
        Enum.join(user_ids, ",")
      )
    else
      nil -> {:error, "server_not_found_in_config"}
      %{} -> {:error, "improper_config"}
      err -> err
    end
  end

  @doc """
  Returns a map representing the current state of the database

  ## Example

      iex> SlackDB.dump()
      %{
        "dog_shelter" => %{
          bot_name: "Jeanie",
          bot_token: "xoxb-shhh...",
          user_token: "xoxp-shhh..."
          channels: %{
            "adopted" => "CHU427918",
            "yet-to-be-adopted" => "CJ57Z7QS1"
          },
          supervisor_channel_id: "CFC6MRQ06",
          supervisor_channel_name: "slackdb-admin",
        }
      }
  """
  @spec dump() :: map()
  def dump() do
    GenServer.call(__MODULE__, {:dump})
  end

  ####################################################################################
  ## GENSERVER CALLBACKS #############################################################
  ####################################################################################
  @impl true
  def init(config) do
    servers = Map.keys(config)

    server_states =
      servers
      |> Enum.map(fn server_name ->
        {server_name,
         read(
           server_name,
           get_in(config, [server_name, :supervisor_channel_name]),
           server_name
         )}
      end)
      |> Enum.map(&initialize_supervisor_channel/1)

    config =
      config
      |> populate_channels(server_states)

    # |> IO.inspect()

    {:ok, config}
  end

  @impl true
  def handle_call(
        {:create, server_name, channel_name, key_phrase, values, all_metadata},
        _from,
        state
      )
      when is_list(values) do
    resp =
      with %{bot_token: bot_token, channels: channels} <- state[server_name] do
        case channels[channel_name] do
          nil ->
            {:error, "channel_name_not_in_database"}

          channel_id ->
            metadata_as_emojis =
              all_metadata |> Enum.map(fn x -> @metadata_to_emoji[x] end) |> Enum.join()

            with {:ok, %{"ts" => thread_ts}} <-
                   Client.chat_postMessage(
                     bot_token,
                     key_phrase <> " #{metadata_as_emojis}",
                     channel_id
                   ) do
              Messages.post_thread(bot_token, channel_id, values, thread_ts)
            else
              err -> err
            end
        end
      else
        nil -> {:error, "server_not_found_in_config"}
        %{} -> {:error, "improper_config"}
        err -> err
      end

    {:reply, resp, state}
  end

  def handle_call({:invite, server_name, channel_name, user_ids}, _from, state)
      when is_list(user_ids) do
    resp =
      with %{user_token: user_token, channels: channels} <- state[server_name] do
        case channels[channel_name] do
          nil ->
            {:error, "channel_name_not_in_database"}

          channel_id ->
            Client.conversations_invite(user_token, channel_id, Enum.join(user_ids, ","))
        end
      else
        nil -> {:error, "server_not_found_in_config"}
        %{} -> {:error, "improper_config"}
        err -> err
      end

    {:reply, resp, state}
  end

  def handle_call({:put_channel, server_name, channel_name, channel_id}, _from, state) do
    new_state = state |> Utils.put_kv_in([server_name, :channels], channel_name, channel_id)
    {:reply, {:ok, new_state}, new_state}
  end

  def handle_call({:archive, server_name, channel_name}, _from, state) do
    resp =
      with %{user_token: user_token, channels: channels} <- state[server_name] do
        case channels[channel_name] do
          nil ->
            {:error, "channel_name_not_in_database"}

          channel_id ->
            Client.conversations_archive(user_token, channel_id)
        end
      else
        nil -> {:error, "server_not_found_in_config"}
        %{} -> {:error, "improper_config"}
        err -> err
      end

    new_state =
      case resp do
        {:ok, _} ->
          {_val, new} = state |> pop_in([server_name, :channels, channel_name])
          new

        {:error, _} ->
          state
      end

    {:reply, resp, new_state}
  end

  def handle_call({:dump}, _from, state), do: {:reply, state, state}

  ####################################################################################
  ## INIT HELPERS ####################################################################
  ####################################################################################

  private do
    defp populate_channels(map, [{server_name, state}]) do
      Utils.put_kv_in(map, [server_name], :channels, state)
    end

    defp populate_channels(map, [{server_name, state} | more_server_states]) do
      Utils.put_kv_in(populate_channels(map, more_server_states), [server_name], :channels, state)
    end

    defp initialize_supervisor_channel({server_name, {:ok, server_state}}) do
      case server_state |> Jason.decode() do
        {:ok, map} -> {server_name, map}
        other -> {server_name, other}
      end
    end

    defp initialize_supervisor_channel({server_name, {:error, _error_message}}) do
      init =
        with %{bot_token: bot_token, supervisor_channel_id: channel_id} <-
               Application.get_env(:slackdb, :servers) |> Map.get(server_name),
             {:ok, %{"ts" => thread_ts}} <-
               Client.chat_postMessage(
                 bot_token,
                 server_name <> " #{@metadata_to_emoji[:single_back]}",
                 channel_id
               ),
             _resp_list <- Messages.post_thread(bot_token, channel_id, "{}", thread_ts) do
          %{}
        else
          nil -> {:error, "server_not_found_in_config"}
          %{} -> {:error, "improper_config"}
          err -> err
        end

      {server_name, init}
    end
  end
end
