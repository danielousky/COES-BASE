require 'rails_admin/config/actions'
require 'rails_admin/config/actions/base'

module RailsAdmin
  module Config
    module Actions
      class Dashboard < RailsAdmin::Config::Actions::Base
        RailsAdmin::Config::Actions.register(self)
        register_instance_option :root? do
          true
        end
        register_instance_option :breadcrumb_parent do
          false
        end
        register_instance_option :link_icon do
          'fa-regular fa-house-flag'
        end
        register_instance_option :show_in_menu do
          false
        end
        register_instance_option :show_in_navigation do
          false
        end        

        register_instance_option :sidebar_label do
          false
        end

        register_instance_option :controller do
          proc do
            admin = current_user&.admin
            if admin
              @dashboard = DashboardDataService.new(admin, session[:period_name])
              @periods = admin.periods.limit(8)
              @multiple_schools = admin.multiple_schools?
            end
            render action: @action.template_name
          end
        end
      end
    end
  end
end