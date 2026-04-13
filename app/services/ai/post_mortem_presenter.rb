# frozen_string_literal: true

module Ai
  class PostMortemPresenter
    def self.to_text(structured_hash)
      new(structured_hash).to_text
    end

    def initialize(structured_hash)
      @h = structured_hash.is_a?(Hash) ? structured_hash.deep_stringify_keys : {}
    end

    def to_text
      <<~TXT.strip
        1) Resumo
        #{@h['summary_result'].presence || '—'}

        2) Causas prováveis
        #{bullet_list(@h['likely_causes'])}

        3) Lacunas de processo
        #{bullet_list(@h['process_gaps'])}

        4) Checklist de melhoria
        #{bullet_list(@h['improvement_checklist'])}

        5) Variância vs processo ruim
        #{@h['variance_vs_bad_process'].presence || '—'}

        6) Comentário sobre seleção / slate
        #{@h['slate_selection_comment'].presence || '—'}

        7) Confiança nesta revisão
        #{@h['confidence_in_review'].presence || '—'}

        8) Alertas de qualidade de dados
        #{@h['data_quality_warning'].presence || '—'}
      TXT
    end

    private

    def bullet_list(arr)
      items = arr.is_a?(Array) ? arr : []
      return '—' if items.empty?

      items.map { |x| "• #{x}" }.join("\n")
    end
  end
end
