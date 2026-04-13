# frozen_string_literal: true

module Ai
  module StructuredOutputs
    # Contrato estrito para `placed_ai_suggestions.ai_post_mortem_structured` (versão 1).
    # Resposta parcial ou tipos errados => estruturalmente inválida (ok: false).
    class PostgameReview
      CONTRACT_VERSION = 1

      REQUIRED_STRING_NON_EMPTY = %w[
        summary_result
        variance_vs_bad_process
        slate_selection_comment
      ].freeze

      REQUIRED_STRING_ALLOW_EMPTY = %w[
        data_quality_warning
      ].freeze

      REQUIRED_ARRAYS_OF_STRINGS = %w[
        likely_causes
        process_gaps
        improvement_checklist
      ].freeze

      REQUIRED_ROOT = (
        REQUIRED_STRING_NON_EMPTY +
        REQUIRED_STRING_ALLOW_EMPTY +
        REQUIRED_ARRAYS_OF_STRINGS +
        %w[confidence_in_review]
      ).freeze

      OPTIONAL_ARRAY = 'leg_notes'

      class << self
        # true somente se o hash satisfaz contrato completo (tipos + conteúdo mínimo).
        def contract_ok?(structured)
          parse(structured)[:ok]
        end

        def parse(structured)
          new(structured).parse
        end
      end

      def initialize(structured)
        @raw = structured
      end

      def parse
        h = normalize_hash(@raw)
        errors = []

        unless h.is_a?(Hash)
          return { ok: false, data: {}, errors: ['root:not_a_hash'] }
        end

        REQUIRED_ROOT.each do |k|
          errors << "missing:#{k}" unless h.key?(k)
        end
        return { ok: false, data: {}, errors: errors } if errors.any?

        REQUIRED_STRING_NON_EMPTY.each do |k|
          v = h[k]
          unless v.is_a?(String)
            errors << "wrong_type:#{k}(expected_string)"
            next
          end

          errors << "empty:#{k}" if v.strip.empty?
        end

        REQUIRED_STRING_ALLOW_EMPTY.each do |k|
          v = h[k]
          errors << "wrong_type:#{k}(expected_string)" unless v.is_a?(String)
        end

        REQUIRED_ARRAYS_OF_STRINGS.each do |k|
          v = h[k]
          unless v.is_a?(Array)
            errors << "wrong_type:#{k}(expected_array)"
            next
          end

          v.each_with_index do |el, i|
            errors << "wrong_element_type:#{k}[#{i}]" unless el.is_a?(String)
          end
        end

        cr = h['confidence_in_review']
        unless confidence_ok?(cr)
          errors << 'wrong_type:confidence_in_review(expected_number_0_1_or_non_empty_string)'
        end

        if h.key?(OPTIONAL_ARRAY)
          ln = h[OPTIONAL_ARRAY]
          if ln.nil?
            errors << 'wrong_type:leg_notes(nil)'
          elsif !ln.is_a?(Array)
            errors << "wrong_type:#{OPTIONAL_ARRAY}(expected_array)"
          else
            ln.each_with_index do |el, i|
              unless el.is_a?(Hash)
                errors << "wrong_element_type:#{OPTIONAL_ARRAY}[#{i}]"
                next
              end

              eh = el.stringify_keys
              errors << "missing:#{OPTIONAL_ARRAY}[#{i}].leg_index" unless eh.key?('leg_index')
              errors << "missing:#{OPTIONAL_ARRAY}[#{i}].note" unless eh.key?('note')
            end
          end
        end

        return { ok: false, data: {}, errors: errors.uniq } if errors.any?

        allowed = REQUIRED_ROOT + [OPTIONAL_ARRAY]
        data = h.slice(*allowed)
        data['_contract_version'] = CONTRACT_VERSION

        { ok: true, data: data, errors: [] }
      end

      private

      def normalize_hash(obj)
        return {} if obj.blank?
        return obj.deep_stringify_keys if obj.is_a?(Hash)

        {}
      end

      def confidence_ok?(cr)
        return false if cr.nil?

        return true if cr.is_a?(Numeric) && cr.to_f >= 0.0 && cr.to_f <= 1.0

        cr.is_a?(String) && cr.strip.present?
      end
    end
  end
end
