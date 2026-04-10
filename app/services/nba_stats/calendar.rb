module NbaStats
  module Calendar
    ET = ActiveSupport::TimeZone['America/New_York']

    def self.scoreboard_today
      ET.today
    end
  end
end
