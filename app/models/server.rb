class Server < ActiveRecord::Base
  class << self
    # DO NOT USE - try Player.fox instead!
    def fox
      find_by_current_role :fox
    end

    # DO NOT USE - try Badger.fox instead!
    def badger
      find_by_current_role :badger
    end

    def main
      find_by_current_role :server
    end

    def make_main(url)
      Server.find_or_create_by(:hostname => url).update_attribute :current_role, 'server'
    end
  end

  has_one :board

  def opponent
    other = self.current_role == 'fox' ? 'badger' : 'fox'
    Server.find_by_current_role other
  end

  def has_opponent?
    !!opponent
  end

  def still_playing?
    return true if !opponent
    !winner? && !loser? && !opponent.winner? && !opponent.loser?
  end

  def won?
    !still_playing? && (winner? || opponent.loser?)
  end

  def lost?
    !still_playing? && (loser? || opponent.winner?)
  end

  def missile_string
    "#{current_role}_missile"
  end

  def killed_string
    "#{current_role}_hit"
  end
end
