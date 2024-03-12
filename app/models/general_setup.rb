# == Schema Information
#
# Table name: general_setups
#
#  id          :bigint           not null, primary key
#  clave       :string
#  description :string
#  valor       :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class GeneralSetup < ApplicationRecord

  def self.enabled_post_qualification?
    var = GeneralSetup.where(clave: "ENABLED_POST_QUALIFICACION").first
    (var&.valor&.casecmp("SI") == 0 or var&.valor&.casecmp("SÍ") == 0) ? true : false
  end

end
