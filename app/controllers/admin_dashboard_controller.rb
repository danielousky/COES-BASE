class AdminDashboardController < ApplicationController
  before_action :require_admin
  skip_before_action :force_password_change!, only: [:enrollment_counts]

  def enrollment_counts
    dashboard = DashboardDataService.new(current_user.admin, session[:period_name])
    json = dashboard.enrollment_counts_json

    if current_user.admin.desarrollador? || current_user.admin.jefe_control_estudio?
      json['active_admins'] = dashboard.active_admins_json(current_user_id: current_user.id)
    end

    render json: json
  end
end
