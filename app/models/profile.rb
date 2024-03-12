# == Schema Information
#
# Table name: profiles
#
#  id         :bigint           not null, primary key
#  name       :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class Profile < ApplicationRecord

	# ASSOCIATIONS:
	has_many :admins

	# VALIDATIONS:
	validates :name, presence: true

end
