# frozen_string_literal: true

namespace :placed_ai do
  desc 'Sincroniza JSONB legs → placed_ai_suggestion_legs e tenta settlement (box score).'
  task sync_legs: :environment do
    n = 0
    PlacedAiSuggestion.find_each do |p|
      p.resync_legs!
      n += 1
    end
    puts "Sincronizado: #{n} bilhete(s)."
  end
end
