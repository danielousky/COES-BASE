class MassEmailJob < ApplicationJob
  queue_as :default

  def perform(user_ids, message)
    User.where(id: user_ids).find_each do |user|
      UserMailer.general(user, message).deliver_later
    end
  end
end
