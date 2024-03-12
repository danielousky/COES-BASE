class CreateTableJoinMentionSubject < ActiveRecord::Migration[7.0]
  def change
    create_join_table :mentions, :subjects do |t|
      t.index [:mention_id, :subject_id], unique: true
      t.index :mention_id
      t.index :subject_id
    end
    add_foreign_key :mentions_subjects, :mentions
    add_foreign_key :mentions_subjects, :subjects
  end
end