class EnhancedController < ActionController::Base
  include ActionController::Live

  before_action :set_paper_trail_whodunnit
  before_action :set_paper_trail_request_info

  def user_for_paper_trail
    current_user ? current_user.id : 'Sistema, consola o no_loggin'
  end

  def info_for_paper_trail
    { ip: request.remote_ip, user_agent: request.user_agent }
  end

  def set_paper_trail_request_info
    return unless PaperTrail::Version.table_exists?
    cols = PaperTrail::Version.column_names
    info = {}
    info[:ip]         = request.remote_ip  if cols.include?('ip')
    info[:user_agent] = request.user_agent if cols.include?('user_agent')
    PaperTrail.request.controller_info = info
  rescue StandardError
    PaperTrail.request.controller_info = {}
  end
end
