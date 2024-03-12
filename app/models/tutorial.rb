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
class Tutorial < ApplicationRecord

  ## Relations
  belongs_to :group_tutorial

  ## HISTORY:
  has_paper_trail on: [:create, :destroy, :update]
  before_create :paper_trail_create
  before_destroy :paper_trail_destroy
  before_update :paper_trail_update

  ## Rich Text
  has_rich_text :description

  ## Storage
  has_one_attached :video
  attr_accessor :remove_video
  after_save { video.purge if remove_video.eql? '1' }
  after_destroy {video.purge}
  
  ## Validations
  validates :name_function, presence: true
  validates :video, presence: true

  # Scopes
  GroupTutorial.all.each do |gt|
    scope gt.name, -> {where('group_tutorial_id': gt.id)}
  end
  scope :todos, -> {where('0 = 0')}


  def name
    self.name_function
  end

  def get_url_temp
    (self.video&.attached?) ? Rails.application.routes.url_helpers.rails_blob_path(self.video, only_path: true) : nil
  end

  rails_admin do
    navigation_label 'Informativos'
    navigation_icon 'fa-regular fa-laptop-code'    
    list do
      scopes ["todos", GroupTutorial.all.map{|gt| gt.name}].flatten
      items_per_page 10
      field :group_tutorial
      field :name_function
      field :video, :active_storage do
        filterable false
        sortable false
        pretty_value do
          bindings[:view].render(partial: '/tutorials/show_video', locals: {url: bindings[:object].get_url_temp, height: '120'})
        end

      end
      field :description do
        filterable false
        sortable false
      end
    end		

    edit do
      field :group_tutorial do
        inline_edit false
      end
      field :name_function
      field :description
      field :video
    end		

    show do
      field :group_tutorial
      field :name_function

      # field :video do |vid|
      #   video_tag Rails.application.routes.url_helpers.rails_blob_url(vid.video.attachment.blob),:controls=>true, :autobuffer=>true,:size => "200x150" rescue nil
      # end

      # field :video do
      #   pretty_value do
      #     bindings[:view].video_tag(bindings[:object].video.attachment.blob)
      #   end
      # end

      field :video do
        pretty_value do
          bindings[:view].render(partial: '/tutorials/show_video', locals: {url: bindings[:object].get_url_temp})
        end

      end


      field :description
    end		
  end


  private
    def paper_trail_update
      changed_fields = self.changes.keys - ['created_at', 'updated_at']
      object = I18n.t("activerecord.models.#{self.model_name.param_key}.one")
      self.paper_trail_event = "¡#{object} actualizado en #{changed_fields.to_sentence}"
    end  

    def paper_trail_create
      object = I18n.t("activerecord.models.#{self.model_name.param_key}.one")
      self.paper_trail_event = "¡Tutorial creado!"
    end  

    def paper_trail_destroy
      object = I18n.t("activerecord.models.#{self.model_name.param_key}.one")
      self.paper_trail_event = "¡Tutorial eliminado!"
    end
end
