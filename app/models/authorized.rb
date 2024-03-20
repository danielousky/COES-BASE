# == Schema Information
#
# Table name: authorizeds
#
#  id              :bigint           not null, primary key
#  can_create      :boolean          default(FALSE)
#  can_delete      :boolean          default(FALSE)
#  can_export      :boolean          default(FALSE)
#  can_import      :boolean          default(FALSE)
#  can_read        :boolean          default(FALSE)
#  can_update      :boolean          default(FALSE)
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  admin_id        :bigint           not null
#  authorizable_id :bigint           not null
#
# Indexes
#
#  index_authorizeds_on_admin_id                      (admin_id)
#  index_authorizeds_on_admin_id_and_authorizable_id  (admin_id,authorizable_id) UNIQUE
#  index_authorizeds_on_authorizable_id               (authorizable_id)
#
# Foreign Keys
#
#  fk_rails_...  (admin_id => admins.user_id) ON DELETE => cascade ON UPDATE => cascade
#  fk_rails_...  (authorizable_id => authorizables.id) ON DELETE => cascade ON UPDATE => cascade
#
class Authorized < ApplicationRecord

  belongs_to :admin
  belongs_to :authorizable

  def authorizable_klazz_constantenize
    authorizable.klazz.constantize if authorizable
  end

  def can_manage?
    can_create? or can_update?
  end

  def can_all?
    aux = true
    if authorizable
      aux = (aux and can_import) if Authorizable::IMPORTABLES.include? authorizable.klazz
      aux = (aux and can_export) unless Authorizable::UNEXPORTABLES.include? authorizable.klazz 
      aux = (aux and can_delete) unless Authorizable::UNDELETABLES.include? authorizable.klazz 
      aux = (aux and can_create) unless Authorizable::UNCREABLES.include? authorizable.klazz
    else
      aux = false
    end 
    aux
  end

  def cannot_all?
    (!can_create and !can_read and !can_update and !can_delete)
  end

  rails_admin do
    visible false
  end
end
