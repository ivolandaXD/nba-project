# frozen_string_literal: true

# Bilhete / props colocadas pelo utilizador, com pernas espelhadas em `placed_ai_suggestion_legs`.
#
# Sincronização de pernas (JSONB → linhas):
# - Corre apenas em `after_commit` quando mudam colunas estruturais (`legs`, `game_id`), para evitar
#   reprocessar em updates de resultado, notas ou post-mortem.
# - Para forçar re-sync (ex.: rake, importação), chamar explicitamente `sync_legs!` e depois `settle_legs!`.
#
# Settlement (box score → hit/miss/push por perna):
# - Não altera o JSONB; só atualiza colunas nas pernas quando há `game_id` + `player_id` + linha válida.
# - Deve correr após `sync_legs!` quando o elenco/box mudou; também é chamado no fim de `sync_legs!`
#   via `resync_legs!` para manter uma API única onde necessário.
class PlacedAiSuggestion < ApplicationRecord
  SLIP_KINDS = %w[single parlay dupla tripla].freeze
  RESULTS = %w[pending win loss void].freeze

  # Mudanças nestas colunas invalidam linhas derivadas em `placed_ai_suggestion_legs`.
  LEGS_STRUCTURAL_COLUMNS = %w[legs game_id].freeze

  belongs_to :user
  belongs_to :game, optional: true
  has_many :placed_ai_suggestion_legs, dependent: :destroy, inverse_of: :placed_ai_suggestion

  after_commit :resync_legs_after_structural_change!, on: %i[create update]

  validates :slip_kind, presence: true, inclusion: { in: SLIP_KINDS }
  validates :description, presence: true
  validates :result, inclusion: { in: RESULTS }
  validates :evaluation_note, length: { maximum: 5000 }, allow_blank: true
  validate :parlay_has_legs
  validate :legs_array_shape

  # Reconstrói pernas a partir do JSONB e aplica settlement (idempotente).
  def resync_legs!
    sync_legs!
    settle_legs!
  end

  def sync_legs!
    PlayerProps::PlacedLegsSyncService.call(self)
  end

  def settle_legs!
    PlayerProps::LegSettlementService.call(self)
  end

  def ai_post_mortem_structured_contract_ok?
    Ai::StructuredOutputs::PostgameReview.contract_ok?(ai_post_mortem_structured)
  end

  def weak_ticket_matching?
    placed_ai_suggestion_legs.any?(&:weak_match?)
  end

  # Retorno em R$ alinhado ao bilhete da casa: vitória = stake × odd; derrota = 0; void = devolução da aposta.
  def implied_return_brl
    return if stake_brl.blank?

    case result
    when 'win'
      return if decimal_odds.blank?

      (stake_brl * decimal_odds).round(2)
    when 'loss'
      BigDecimal('0')
    when 'void'
      stake_brl.round(2)
    end
  end

  def parlay_has_legs
    return if slip_kind == 'single'

    errors.add(:legs, 'precisa de pelo menos uma perna') unless legs.is_a?(Array) && legs.any?
  end

  def legs_array_shape
    return unless legs.is_a?(Array) && legs.any?

    legs.each_with_index do |row, i|
      h = row.is_a?(Hash) ? row.stringify_keys : {}
      next if h['player'].present? && h['market'].present? && h['line'].present?

      errors.add(:legs, "perna #{i + 1} inválida (precisa player, market, line)")
    end
  end

  private

  def resync_legs_after_structural_change!
    return unless persisted?

    ch = previous_changes
    return if ch.blank?
    return unless (ch.keys & self.class::LEGS_STRUCTURAL_COLUMNS).any?

    resync_legs!
  rescue StandardError => e
    Rails.logger.error("[PlacedAiSuggestion#resync_legs_after_structural_change!] #{e.class}: #{e.message}")
  end
end
