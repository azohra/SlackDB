defmodule SlackDB do
  @moduledoc """
  GenServer that is responsible for all interactions with SlackDB.

  On startup, the server will load into memory the current state of the
  server (as described in the supervisor channel). All changes to state
  (channel additions and archivals) made through this API will be updated
  and persisted in the supervisor channel
  """
  require Logger
  alias SlackDB.Channels
  alias SlackDB.Client
  alias SlackDB.Key
  alias SlackDB.Messages
  alias SlackDB.Search
  alias SlackDB.Server
  alias SlackDB.Utils

  @callback read(String.t(), String.t(), String.t()) ::
              {:error, String.t()} | {:ok, SlackDB.Key.value()}

  @callback read(String.t(), String.t(), String.t(), keyword()) ::
              {:error, String.t()} | {:ok, SlackDB.Key.value()}

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

  defp client(), do: Application.get_env(:slackdb, :client_adapter, Client)
  defp search(), do: Application.get_env(:slackdb, :search_adapter, Search)
  defp messages(), do: Application.get_env(:slackdb, :messages_adapter, Messages)
  defp channels(), do: Application.get_env(:slackdb, :channels_adapter, Channels)
  defp key(), do: Application.get_env(:slackdb, :key_adapter, Key)

  ####################################################################################
  ## PUBLIC API ######################################################################
  ####################################################################################

  @doc """
  Create a key/value pair in the specified server and channel of the given type

  This essentially overwrites the key if it already exist. It posts a new message that will always be prioritized by `read/4` because it is more recent.

  The value passed in may be either a String or a list of Strings that will be posted in the key's thread, in order.
  You can specify additional metadata to be added to the key using an optional list.

  This function returns an error tuple or a list of tuples indicating the result of posting each value.
  The channel that is specified must exist in the scope of the server.

  ## Example

      iex> SlackDB.create("dog_shelter", "adopted", "Beagles", ["Buddy", "Rufus"], :multiple, [:undeletable])
      {:ok, [
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
      ]}
  """
  @spec create(
          String.t(),
          String.t(),
          String.t(),
          SlackDB.Key.value(),
          SlackDB.Key.type(),
          list(SlackDB.Key.more_metadata())
        ) :: {:error, String.t()} | list(tuple())
  def create(server_name, channel_name, key_phrase, value, key_type, add_metadata \\ [])

  def create(server_name, channel_name, key_phrase, value, key_type, add_metadata)
      when is_binary(value) and is_list(add_metadata) and is_atom(key_type),
      do: create(server_name, channel_name, key_phrase, [value], key_type, add_metadata)

  def create(server_name, channel_name, key_phrase, values, key_type, add_metadata)
      when is_list(values) and is_list(add_metadata) and is_atom(key_type) do
    with nil <- Utils.check_schema(key_phrase),
         :ok <- validate_values(values) do
      GenServer.call(
        Server,
        {:create, server_name, channel_name, key_phrase, values, [key_type | add_metadata]}
      )
    else
      {:error, msg} -> {:error, msg}
      _err -> {:error, "invalid_key_phrase"}
    end
  end

  @doc """
  Reads a key in the given server and channel, raising an error if anything went wrong

  This will always pull from the most recently posted message that matches the key schema.

  ## Options
  * `only_bot?` - boolean, whether to only search for bot-made keys. Defaults to true.

  ## Example

      iex> SlackDB.read!("dog_shelter", "adopted", "Beagles")
      ["Buddy", "Rufus"]
  """
  @spec read!(String.t(), String.t(), String.t(), keyword()) :: SlackDB.Key.value()
  def read!(server_name, channel_name, key_phrase, opts \\ []) do
    only_bot? = Keyword.get(opts, :only_bot?, true)

    read(server_name, channel_name, key_phrase, only_bot?: only_bot?)
    |> case do
      {:ok, val} -> val
      {:error, msg} -> raise msg
    end
  end

  @doc """
  Reads a key in the given server and channel

  This will always pull from the most recently posted message that matches the key schema.

  ## Options
  * `only_bot?` - boolean, whether to only search for bot-made keys. Defaults to true.

  ## Example

      iex> SlackDB.read("dog_shelter", "adopted", "Beagles")
      {:ok, ["Buddy", "Rufus"]}
  """
  @spec read(String.t(), String.t(), String.t(), keyword()) ::
          {:error, String.t()} | {:ok, SlackDB.Key.value()}
  def read(server_name, channel_name, key_phrase, opts \\ []) do
    only_bot? = Keyword.get(opts, :only_bot?, true)

    with {:ok, key} <- search().search(server_name, channel_name, key_phrase, only_bot?) do
      # IO.inspect(key)
      key().get_value(key)
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
      {:ok, [
        ok: %{
          "channel" => "CHU427918",
          "message" => %{...},
          "ok" => true,
          "ts" => "1556129092.000800"
        },
      ]}
  """
  @spec update(String.t(), String.t(), String.t(), SlackDB.Key.value()) ::
          {:error, String.t()} | {:ok, list(tuple())}
  def update(server_name, channel_name, key_phrase, value) when is_binary(value),
    do: update(server_name, channel_name, key_phrase, [value])

  def update(server_name, channel_name, key_phrase, values) when is_list(values) do
    with :ok <- validate_values(values),
         {:ok, key} <- search().search(server_name, channel_name, key_phrase, false) do
      cond do
        :constant in key.metadata ->
          {:error, "cannot_update_constant_key"}

        true ->
          messages().wipe_thread(key, include_key?: false)
          messages().post_thread(key, values)
      end
    else
      err -> err
    end
  end

  @doc """
  Deletes a key and it's associated thread

  Beware of rate_limiting issues discussed in the README

  This function returns an error tuple or a list of tuples indicating the result of deleting each message in the thread.

  ## Example

      iex> SlackDB.delete("dog_shelter", "yet-to-be-adopted", "Chihuahuas")
      {:ok, [
        ok: %{
          "channel" => "CHU427918",
          "message" => %{...},
          "ok" => true,
          "ts" => "1556129092.000800"
        },
      ]}
  """
  @spec delete(String.t(), String.t(), String.t()) :: {:error, String.t()} | {:ok, list(tuple())}
  def delete(server_name, channel_name, key_phrase) do
    with {:ok, key} <- search().search(server_name, channel_name, key_phrase, false) do
      cond do
        :undeletable in key.metadata -> {:error, "cannot_delete_undeletable_key"}
        true -> messages().wipe_thread(key, include_key?: true)
      end
    else
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
      {:ok, [
        ok: %{
          "channel" => "CHU427918",
          "message" => %{...},
          "ok" => true,
          "ts" => "1556129092.000800"
        }
      ]}
  """
  @spec append(String.t(), String.t(), String.t(), SlackDB.Key.value()) ::
          {:ok, [tuple()]} | {:error, String.t()}
  def append(server_name, channel_name, key_phrase, value) when is_binary(value),
    do: append(server_name, channel_name, key_phrase, [value])

  def append(server_name, channel_name, key_phrase, values) when is_list(values) do
    with :ok <- validate_values(values),
         {:ok, key} <-
           search().search(server_name, channel_name, key_phrase, only_bot?: true) do
      cond do
        :constant in key.metadata ->
          {:error, "cannot_append_to_constant_key"}

        true ->
          messages().post_thread(key, values)
      end
    else
      err -> err
    end
  end

  @doc """
  Creates a new channel and updates the current state of the database

  A channel must exist in the current state of the databse to create keys or to invite users.
  Since bots cannot add themselves to channels, you must also add the bot manually once the channel is created.

  ## Options
  * `is_private` - boolean, whether or not the channel is private. Defaults to false.

  ## Example

      iex> SlackDB.new_channel("dog_shelter", "volunteers", false)
      {:ok, %{...new_db_state...}}
  """
  @spec new_channel(String.t(), String.t(), keyword()) :: {:error, String.t()} | {:ok, map()}
  def new_channel(server_name, channel_name, opts \\ []) do
    with [user_token, sprvsr_chnl_name] <-
           Utils.get_tokens(server_name, [:user_token, :supervisor_channel_name]),
         {:ok, %{"name" => channel_name, "id" => channel_id}} <-
           client().conversations_create(user_token, channel_name,
             is_private: Keyword.get(opts, :is_private, false)
           ),
         {:ok, new_state} <-
           GenServer.call(Server, {:put_channel, server_name, channel_name, channel_id}),
         {:ok, [ok: _resp]} <-
           append(
             server_name,
             sprvsr_chnl_name,
             server_name,
             new_state |> get_in([server_name, :channels]) |> Jason.encode!()
           ) do
      {:ok, new_state}
    else
      err -> err
    end
  end

  @doc """
  Includes an existing channel and updates the state of the database

  A channel must exist in the current state of the databse to create keys or to invite users
  Since bots cannot add themselves to channels, you must also add the bot manually once the channel is included.

  ## Example

      iex> SlackDB.include_channel("dog_shelter", "employees")
      {:ok, %{...new_db_state...}}
  """
  @spec include_channel(String.t(), String.t()) :: {:error, String.t()} | {:ok, map()}
  def include_channel(server_name, channel_name) do
    with [sprvsr_chnl_name] <- Utils.get_tokens(server_name, [:supervisor_channel_name]),
         {:ok, convo_list} <- channels().get_all_convos(server_name),
         %{"id" => channel_id} <-
           convo_list |> Enum.find(fn chnl -> chnl["name"] == channel_name end),
         {:ok, new_state} <-
           GenServer.call(Server, {:put_channel, server_name, channel_name, channel_id}),
         {:ok, [{:ok, _resp}]} <-
           append(
             server_name,
             sprvsr_chnl_name,
             server_name,
             new_state |> get_in([server_name, :channels]) |> Jason.encode!()
           ) do
      {:ok, new_state}
    else
      nil -> {:error, "channel_not_found"}
      err -> err
    end
  end

  @doc """
  Archives a channel and removes it from the state of the database

  ## Example

      iex> SlackDB.archive_channel("dog_shelter", "coops-winter-2019")
      {:ok, %{...new_db_state...}}
  """
  @spec archive_channel(String.t(), String.t()) :: {:error, String.t()} | {:ok, map()}
  def archive_channel(server_name, channel_name) do
    with [sprvsr_chnl_name] <- Utils.get_tokens(server_name, [:supervisor_channel_name]),
         {:ok, _resp} <- GenServer.call(Server, {:archive, server_name, channel_name}),
         new_state <- GenServer.call(Server, {:dump}),
         {:ok, [{:ok, _resp}]} <-
           append(
             server_name,
             sprvsr_chnl_name,
             server_name,
             new_state |> get_in([server_name, :channels]) |> Jason.encode!()
           ) do
      {:ok, new_state}
    else
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
      when is_list(user_ids) and length(user_ids) in 1..29 do
    GenServer.call(Server, {:invite, server_name, channel_name, user_ids})
  end

  @doc """
  Invites a user_id or a list of user_ids to the supervisor channel of a specified server

  ## Example

      iex> SlackDB.invite_supervisors("dog_shelter", ["USERID1", "USERID2"])
      {:ok, %{"name" => "slackdb-admin", "id" => "CFC6MRQ06"}}
  """
  @spec invite_supervisors(String.t(), String.t() | list(String.t())) ::
          {:error, String.t()} | {:ok, map()}
  def invite_supervisors(server_name, user_id) when is_binary(user_id),
    do: invite_supervisors(server_name, [user_id])

  def invite_supervisors(server_name, user_ids)
      when is_list(user_ids) and length(user_ids) in 1..29 do
    channels().invite_to_channel(server_name, :supervisor, user_ids)
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
    GenServer.call(Server, {:dump})
  end

  ####################################################################################
  ## PRIVATE HELPERS #################################################################
  ####################################################################################

  # checks a list of values to ensure that none of them match the key schema
  defp validate_values([]), do: :ok

  defp validate_values([value | other_values]) do
    case Utils.check_schema(value) do
      nil -> validate_values(other_values)
      _ -> {:error, "values must not match key schema"}
    end
  end
end
