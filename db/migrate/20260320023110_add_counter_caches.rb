class AddCounterCaches < ActiveRecord::Migration[7.0]
  def up
    add_column :grades, :enroll_academic_processes_count, :integer, default: 0, null: false
    add_column :sections, :academic_records_count, :integer, default: 0, null: false
    add_column :courses, :sections_count, :integer, default: 0, null: false

    # Poblar contadores existentes
    Grade.find_each do |grade|
      Grade.reset_counters(grade.id, :enroll_academic_processes)
    end

    Section.find_each do |section|
      Section.reset_counters(section.id, :academic_records)
    end

    Course.find_each do |course|
      Course.reset_counters(course.id, :sections)
    end
  end

  def down
    remove_column :grades, :enroll_academic_processes_count
    remove_column :sections, :academic_records_count
    remove_column :courses, :sections_count
  end
end
