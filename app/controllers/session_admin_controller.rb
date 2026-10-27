
class SessionAdminController < ApplicationController

  before_action :require_admin

  def change_period_session
    session[:period_name] = params[:nuevo]
    
    flash[:success] = "Periodo cambiado con éxito al #{session[:period_name]}"
    redirect_back fallback_location: rails_admin_path
  end

end # fin controller
