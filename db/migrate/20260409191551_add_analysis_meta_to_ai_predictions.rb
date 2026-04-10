class AddAnalysisMetaToAiPredictions < ActiveRecord::Migration[5.2]
  def change
    add_column :ai_predictions, :analysis_meta, :jsonb, null: false, default: {}
  end
end
