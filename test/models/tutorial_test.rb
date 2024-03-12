# == Schema Information
#
# Table name: tutorials
#
#  id                :bigint           not null, primary key
#  name_function     :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  group_tutorial_id :bigint           not null
#
# Indexes
#
#  index_tutorials_on_group_tutorial_id  (group_tutorial_id)
#
# Foreign Keys
#
#  fk_rails_...  (group_tutorial_id => group_tutorials.id)
#
require "test_helper"

class TutorialTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
