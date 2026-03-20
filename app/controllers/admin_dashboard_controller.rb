class AdminDashboardController < ApplicationController
  before_action :authenticate_user!

  def enrollment_counts
    return head(:forbidden) unless current_user&.admin?

    dashboard = DashboardDataService.new(current_user.admin, session[:period_name])
    render json: dashboard.enrollment_counts_json
  end
end
