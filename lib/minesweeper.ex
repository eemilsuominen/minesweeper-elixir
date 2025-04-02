defmodule Minesweeper do
  use Application

  def start(_type, _args) do
    w = get_input("Enter grid width(suggested 20-30): ", 10, 100)
    h = get_input("Enter grid height (suggested 10-15): ", 10, 50)
    m = get_input("Enter number of mines (suggested area / 10): ", 1, (w * h - 1))

    game_state = %{
      width: w,
      height: h,
      mines: m,
      grid: create_grid(w, h, m),
      cursor: {0, 0},
      revealed: MapSet.new(),
      flagged: MapSet.new(),
      game_over: false,
      win: false
    }

    Task.start_link(fn ->
      game_loop(game_state)
    end)
  end

  def main do
    Application.ensure_all_started(:minesweeper)
    Process.sleep(:infinity)
  end

  def get_input(prompt, min,  max) do
    input = IO.gets(prompt) |> String.trim()
    case Integer.parse(input) do
      {num, ""} when num >= min and num <= max ->
        num
    _ ->
        IO.puts("Invalid input. Enter a number between #{min} and #{max}.")
        get_input(prompt, min, max)
    end
  end

  def game_loop(game) do
    print_grid(game)

    if game.game_over do
      System.halt()
    end

    new_game = case read_input() do
      {:arrow, direction} ->
        move_cursor(game, direction)
      :reveal ->
        reveal_square(game)
      :flag ->
        put_flag(game)
      _ ->
        game
    end

    game_loop(new_game)
  end

  def create_grid(width \\ 20, height \\ 10, mines \\ 10) do
    all_coords = for x <- 0..(width - 1), y <- 0..(height - 1), do: {x, y}

    mine_coords = Enum.take_random(all_coords, mines) |> MapSet.new()

    Enum.reduce(all_coords, %{}, fn {x, y}, grid ->
      value = if MapSet.member?(mine_coords, {x, y}) do
        :mine
      else
        Enum.count(get_neighbours(x, y, width, height), fn coord ->
          MapSet.member?(mine_coords, coord)
        end)
      end

      Map.put(grid, {x, y}, value)
    end)
  end

  def reveal_square(game) do
    if game.game_over do
      game
    else
      square = game.cursor

      if MapSet.member?(game.revealed, square) || MapSet.member?(game.flagged, square) do
        game
      else
        case Map.get(game.grid, square) do
          # reveal all mines if hit and end game
          :mine ->
            all_mines = Enum.filter(game.grid, fn {_, v} -> v == :mine end)
                       |> Enum.map(fn {coord, _} -> coord end)
                       |> MapSet.new()
            %{game | game_over: true, revealed: MapSet.union(game.revealed, all_mines)}
          0 ->
            new_revealed = reveal_empty(game, square)
            new_game = %{game | revealed: new_revealed}
            check_win(new_game)
          _ ->
            new_revealed = MapSet.put(game.revealed, square)
            new_game = %{game | revealed: new_revealed}
            check_win(new_game)
        end
      end
    end
  end

  def put_flag(game) do
    if game.game_over do
      game
    else
      square = game.cursor
      if MapSet.member?(game.revealed, square) do
        game
      else
        new_flagged = if MapSet.member?(game.flagged, square) do
          MapSet.delete(game.flagged, square)
        else
          MapSet.put(game.flagged, square)
        end
        %{game | flagged: new_flagged}
      end
    end
  end

  def reveal_empty(game, {x, y} = square) do
    if MapSet.member?(game.revealed, square) || MapSet.member?(game.flagged, square) ||
       x < 0 || x >= game.width || y < 0 || y >= game.height do
      game.revealed
    else
      new_revealed = MapSet.put(game.revealed, square)

      case Map.get(game.grid, square) do
        0 ->
          neighbours = get_neighbours(x, y, game.width, game.height)
          Enum.reduce(neighbours, new_revealed, fn neighbour, acc ->
            reveal_empty(%{game | revealed: acc}, neighbour)
          end)
        _ ->
          new_revealed
      end
    end
  end

  def get_neighbours(x, y, width, height) do
    for d_x <- -1..1, d_y <- -1..1, # -1, 0, 1 x and y axis from selected square
        n_x = x + d_x, n_y = y + d_y, #neigbour x and y
        n_x >= 0 and n_x < width,
        n_y >= 0 and n_y < height,
        {d_x, d_y} != {0, 0},
        do: {n_x, n_y} #return neighbour
  end

  def check_win(game) do
    not_mines = Enum.count(game.grid, fn {_, v} -> v != :mine end)

    if MapSet.size(game.revealed) == not_mines do
      %{game | win: true, game_over: true}
    else
      game
    end
  end

  def print_grid(game) do
    # clear screen
    IO.write("\e[2J\e[H")

    IO.puts("Minesweeper - Use arrow keys to move, Space to reveal, F to flag. Enter to confirm keystrokes.")
    IO.puts("The game is won if all empty squares are revealed. The game is lost if a mine is revealed.")

    IO.write(" ")
    IO.puts(String.duplicate("_", game.width + 2))

    for y <- 0..(game.height - 1) do
      IO.write("| ")
      for x <- 0..(game.width - 1) do
        square = {x, y}
        char = cond do
          # highlight cursor
          game.cursor == square ->
            "\e[7m" <>
            (cond do
              MapSet.member?(game.flagged, square) -> "F"
              MapSet.member?(game.revealed, square) ->
              case Map.get(game.grid, square) do
                0 -> " " #space if no neighbour mines
                :mine -> "*" #bomba
                num -> "#{num}" #number of neighbour mines
              end
              true -> "?"
            end) <>
            "\e[0m"
            #normal squares same but without highlight
          MapSet.member?(game.flagged, square) -> "F"
          MapSet.member?(game.revealed, square) ->
            case Map.get(game.grid, square) do
              0 -> " "
              :mine -> "*"
              num -> "#{num}"
            end
          true -> "?"
        end
        IO.write(char)
      end
      IO.write(" |")
      IO.puts("")
    end

    IO.write("|")
    IO.write((String.duplicate("_", game.width + 2)))
    IO.puts("|")


    if game.game_over do
      if game.win do
        IO.puts("\nYou found all empty squares! You won!")
      else
        IO.puts("\nYou hit a mine! Game over!")
      end
    end
  end

  def read_input do
    case IO.getn("", 1) do
      "\e" ->
        case IO.getn("", 2) do
          "[A" -> {:arrow, :up}
          "[B" -> {:arrow, :down}
          "[C" -> {:arrow, :right}
          "[D" -> {:arrow, :left}
          _ -> :unknown
        end
      " " -> :reveal
      "f" -> :flag
      _ -> :unknown
    end
  end

  def move_cursor(game, direction) do
    {x, y} = game.cursor
    new_pos = case direction do
      :up -> {x, max(0, y - 1)}
      :down -> {x, min(game.height - 1, y + 1)}
      :left -> {max(0, x - 1), y}
      :right -> {min(game.width - 1, x + 1), y}
    end
    %{game | cursor: new_pos}
  end
end
