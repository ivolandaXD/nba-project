# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::StructuredOutputs::PostgameReview do
  let(:valid) do
    {
      'summary_result' => 'ok',
      'likely_causes' => ['a'],
      'process_gaps' => [],
      'improvement_checklist' => ['x'],
      'variance_vs_bad_process' => 'variância',
      'slate_selection_comment' => 'n/a',
      'confidence_in_review' => 0.7,
      'data_quality_warning' => ''
    }
  end

  it 'accepts a complete valid payload' do
    out = described_class.parse(valid)
    expect(out[:ok]).to be true
    expect(out[:data]['summary_result']).to eq('ok')
    expect(described_class.contract_ok?(valid)).to be true
  end

  it 'rejects missing keys' do
    out = described_class.parse('summary_result' => 'only')
    expect(out[:ok]).to be false
    expect(out[:errors]).to include(match(/missing:/))
  end

  it 'rejects empty summary_result' do
    bad = valid.merge('summary_result' => '   ')
    out = described_class.parse(bad)
    expect(out[:ok]).to be false
    expect(out[:errors]).to include('empty:summary_result')
  end

  it 'rejects non-string array elements' do
    bad = valid.merge('likely_causes' => [1, 2])
    out = described_class.parse(bad)
    expect(out[:ok]).to be false
    expect(out[:errors]).to include(match(/wrong_element_type:likely_causes/))
  end

  it 'rejects invalid confidence_in_review' do
    bad = valid.merge('confidence_in_review' => '')
    out = described_class.parse(bad)
    expect(out[:ok]).to be false
    expect(out[:errors].join).to include('confidence_in_review')
  end

  it 'rejects numeric confidence outside 0..1' do
    bad = valid.merge('confidence_in_review' => 1.4)
    out = described_class.parse(bad)
    expect(out[:ok]).to be false
    expect(out[:errors].join).to include('confidence_in_review')
  end

  it 'rejects malformed leg_notes' do
    bad = valid.merge('leg_notes' => [{ 'leg_index' => 0 }])
    out = described_class.parse(bad)
    expect(out[:ok]).to be false
    expect(out[:errors].join).to include('leg_notes')
  end
end
