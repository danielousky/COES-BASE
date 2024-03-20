# == Schema Information
#
# Table name: billboards
#
#  id         :bigint           not null, primary key
#  active     :boolean          default(FALSE)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
require "test_helper"

class BillboardTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
