module PlayerProps
  # Modificadores percentuais simples sobre P(over), conforme contexto manual.
  class ContextAdjustor
    Modifier = Struct.new(:key, :label, :delta, keyword_init: true)

    def self.call(probability_over:, manual_context:, spread: nil)
      p = probability_over.to_f
      ctx = manual_context.deep_symbolize_keys
      mods = []

      case ctx[:key_teammate_out].to_s
      when 'strong'
        mods << Modifier.new(key: 'key_teammate_out', label: 'Desfalque chave no elenco (forte)', delta: 0.10)
      when 'moderate'
        mods << Modifier.new(key: 'key_teammate_out', label: 'Desfalque chave no elenco (moderado)', delta: 0.05)
      end

      mods << Modifier.new(key: 'matchup_favorable', label: 'Matchup favorável (manual)', delta: 0.05) if truthy?(ctx[:matchup_favorable])

      mods << Modifier.new(key: 'pace', label: 'Ritmo alto (pace)', delta: 0.03) if ctx[:pace].to_s.downcase == 'alto'

      mods << Modifier.new(key: 'back_to_back', label: 'Back-to-back', delta: -0.05) if truthy?(ctx[:is_back_to_back])

      abs_spread = spread.to_f.abs
      if abs_spread >= 12
        mods << Modifier.new(key: 'blowout', label: 'Risco de blowout (|spread| ≥ 12)', delta: -0.10)
      elsif abs_spread >= 8
        mods << Modifier.new(key: 'blowout', label: 'Risco de blowout (|spread| ≥ 8)', delta: -0.05)
      end

      r = ctx[:opponent_defense_rank_vs_position].to_s.strip
      if r.match?(/\A\d+\z/)
        rv = r.to_i
        if rv <= 5
          mods << Modifier.new(key: 'defense_rank', label: "Defesa forte vs posição (rank #{rv})", delta: -0.03)
        elsif rv >= 20
          mods << Modifier.new(key: 'defense_rank', label: "Defesa fraca vs posição (rank #{rv})", delta: 0.03)
        end
      end

      total = mods.sum(&:delta)
      adj = p + total
      adj = [[adj, 0.02].max, 0.98].min

      {
        adjusted_probability: adj,
        modifier_total: total,
        modifiers: mods.map do |m|
          { 'key' => m.key, 'label' => m.label, 'delta_percent_points' => (m.delta * 100).round(2) }
        end
      }
    end

    def self.truthy?(v)
      v == true || v.to_s.match?(/\A(1|true|yes|on)\z/i)
    end
  end
end
