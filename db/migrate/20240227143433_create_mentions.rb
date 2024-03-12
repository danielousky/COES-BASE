class CreateMentions < ActiveRecord::Migration[7.0]
  def change
    create_table :mentions do |t|
      t.string :name
      t.references :study_plan, null: false, foreign_key: true
      t.integer :total_required_subjects, null: false
      t.timestamps
    end
  end
end