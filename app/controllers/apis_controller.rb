class ApisController < ApplicationController
  skip_before_filter :verify_authenticity_token
  before_filter :get_player_uuid
  
  # Entry point: Please sir, can I play?
  def index
    if Player.fox.nil? || Player.fox.hostname == @player_uuid
      player = Player.find_or_create_fox(@player_uuid)
    elsif Player.badger.nil? || Player.badger.hostname == @player_uuid
      player = Player.find_or_create_badger(@player_uuid)
    else
      player = nil
    end

    if player 
      @out = {:animal => player.current_role, :board => generate_board, :pieces => generate_pieces, :ready_to_go => player.has_opponent?}
      render :text => @out.to_json
    else
      @out = { :result => "Too late: Sorry someone has beat you to it" }
      render :text => @out.to_json, :status => 500
    end
  end

  def create
    @out = {:result => 'Success: You are ready to play!'}
    @animal = Player.find_by_animal(params[:animal])
    if @animal.nil?
      @out = { :result => 'No such animal: You need to call the index action first.'}
      @error = true
    elsif !unparse_position_parameters
      @out = { :result => 'Missing positions: either positions[horizontal] or positions[vertical] must a string of json representing a 2d array. Recieved ' + params.inspect }
      @error = true
    elsif attempting_to_place_incorrect_pieces?
      @out = { :result => "Incorrect pieces: You were given #{generate_pieces.inspect} and tried to place #{@piece_names}" }
      @error = true
    elsif @animal.board
      @out = { :result => 'Repeated setup: You must not create multiple boards for the same player' }
      @error = true
    else
      board = Board.new
      @animal.board = board
      @animal.save

      fill_board_from_params board
    end

    if @error
      @animal.update_attribute :loser, true if @animal
      @animal.opponent.update_attribute :winner, true if @animal && @animal.opponent
      @out[:winner] = Player.winner.current_role
      render :text => @out.to_json, :status => 500
    else
      render :text => @out.to_json
    end
  end

  def update
    @animal = Player.find_by_animal(params[:animal])
    if @animal.still_playing?
      x, y = params[:shot].map &:to_i

      if @animal.nil?
        @out = { :result => 'No such animal: You need to call the index and create actions first.'}
        @error = true
      elsif Player.game_over?
        @out = {:result => @animal.won? ? "win" : "lose", :winner => Player.winner.current_role}
        @error = true
      elsif !@animal.opponent or !@animal.opponent.board
        @out = {:result => 'AWOL', :message => "The opponent has not set up their board yet. Try again in a second."}
      else
        board = @animal.opponent.board
        cell = board.get_cell x, y
        board.register_shot(x,y)
        if cell.nil? || cell == @animal.missile_string
          board.fill_cell x, y, @animal.missile_string 
          @out = {:result => 'miss'}
        elsif cell[@animal.opponent.current_role] # match substring in case we've hit this cell before
          opponent_kill_string = @animal.opponent.killed_string
          board.fill_cell x, y, opponent_kill_string
          killed_enemies = board.count_cells_containing(opponent_kill_string)
          if killed_enemies == possible_kills_per_player
            @animal.update_attribute :winner, true
            @animal.opponent.update_attribute :loser, true
            @out = {:result => 'win', :winner => Player.winner.current_role}
          else 
            @out = {:result => 'hit', :killed_enemies => killed_enemies}
          end
        end
        board.save
      end
    else
      @out = {:result => @animal.won? ? "win" : "lose", :winner => Player.winner.current_role}
    end

    if @error
      render :text => @out.to_json, :status => 500
    else
      render :text => @out.to_json
    end
  end

  private
  def get_player_uuid
    @player_uuid = params[:uuid]
  end

  def generate_pieces
    [5,4,3,2,1]
  end

  def possible_kills_per_player
    generate_pieces.inject(0) { |acc, piece| acc + piece }
  end

  def generate_board
    [8,8]
  end

  def unparse_position_parameters
    return false if params[:positions].nil?
    return false unless params[:positions][:horizontal].is_a?(String) or params[:positions][:vertical].is_a?(String)
    params[:positions][:horizontal] = JSON.parse params[:positions][:horizontal] if params[:positions][:horizontal]
    params[:positions][:vertical] = JSON.parse params[:positions][:vertical] if params[:positions][:vertical]
    return params[:positions][:horizontal] || params[:positions][:vertical]
  rescue Exception => e
    return false
  end

  def attempting_to_place_incorrect_pieces?
    params[:positions][:horizontal] ||= []
    params[:positions][:vertical] ||= []

    placed_pieces = params[:positions][:horizontal]  + params[:positions][:vertical]

    @piece_names = placed_pieces.map(&:first).map(&:to_i)

    generate_pieces.sort != @piece_names.sort
  end

  def fill_board_from_params(board)
    params[:positions][:vertical].each do |length, x, y|
      length.to_i.times do |relative_position|
        board.fill_cell!(x.to_i, y.to_i + relative_position, @animal.current_role)
      end
    end
    params[:positions][:horizontal].each do |length, x, y|
      length.to_i.times do |relative_position|
        board.fill_cell!(x.to_i + relative_position, y.to_i, @animal.current_role)
      end
    end
    board.save
  rescue Board::LayoutError => e
    @error = true
    @out = { :result => e.message }
  end
end