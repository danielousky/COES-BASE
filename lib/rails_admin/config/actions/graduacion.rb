module RailsAdmin
  module Config
    module Actions
      # Proceso Graduación (FHE).
      # Flujo: Tesista → Posible Graduando → Graduando → Graduado.
      # "Tesista" es derivado (Grade cursante con tesis activa); el resto son
      # valores de Grade#graduate_status. Toda la lógica de transición vive en
      # el modelo Grade (promover_graduacion! / revertir_graduacion!).
      class Graduacion < RailsAdmin::Config::Actions::Base
        RailsAdmin::Config::Actions.register(self)

        SORT_COLUMNS = {
          'ci'   => 'users.ci',
          'name' => 'users.last_name, users.first_name',
          'plan' => 'study_plans.code'
        }.freeze

        TABS = %w[tesistas posibles graduandos graduados].freeze

        register_instance_option :root? do
          true
        end

        register_instance_option :http_methods do
          %i[get post]
        end

        register_instance_option :link_icon do
          'fa-solid fa-user-graduate'
        end

        register_instance_option :pjax? do
          false
        end

        register_instance_option :breadcrumb_parent do
          [:dashboard]
        end

        # Visible solo vía el enlace del sidebar (SIDEBAR_EXTRA_LINKS), no en el menú.
        register_instance_option :show_in_menu do
          false
        end

        register_instance_option :show_in_navigation do
          false
        end

        register_instance_option :controller do
          # Se sale del proc con `next`, nunca con `return`: RailsAdmin lo instance_eval'a
          # fuera del método donde se definió y `return` levanta LocalJumpError.
          proc do
            if request.post?
              # --- Promoción / reversión de estado ---
              # Preserva el contexto de trabajo (pestaña, búsqueda, orden, página) al volver.
              back = { action: :graduacion, controller: 'rails_admin/main',
                       tab: params[:current_tab], q: params[:current_q].presence,
                       sort: params[:current_sort].presence, direction: params[:current_direction].presence,
                       page: params[:current_page].presence }
              unless current_ability.can?(:manage, :graduacion)
                flash[:error] = "No tiene permiso para modificar el estado de graduación."
                redirect_to url_for(back)
                next
              end
              grade = Grade.find(params[:grade_id])
              begin
                previous_status = grade.graduate_status
                previous_perm   = grade.current_permanence_status
                if params[:revert] == '1'
                  grade.revertir_graduacion!
                  msg = "#{grade.student.name} devuelto de #{previous_status.titleize} a #{grade.graduate_status.titleize}."
                else
                  grade.promover_graduacion!(params[:promote_to])
                  msg = "#{grade.student.name} promovido a #{grade.graduate_status.titleize}."
                end
                if previous_perm != grade.current_permanence_status
                  msg += " Permanencia actualizada de #{previous_perm.titleize} a #{grade.current_permanence_status.titleize}."
                end
                flash[:success] = msg
              rescue Grade::TransicionGraduacionInvalida => e
                flash[:error] = e.message
              end
              redirect_to url_for(back)

            elsif params[:recaudos_for].present?
              # --- Modal de recaudos por estudiante (+ descarga xlsx de asignaturas) ---
              @grade = Grade.includes(:study_plan, student: :user).find(params[:recaudos_for])
              @current_tab = params[:current_tab]
              approved = @grade.academic_records.aprobado.joins(:subject)
                               .includes(:subject, enroll_academic_process: { academic_process: :period })
                               .order('subjects.code ASC')

              if params[:download] == 'xlsx'
                require 'xlsxtream'
                user = @grade.student.user
                io = StringIO.new
                Xlsxtream::Workbook.open(io) do |xlsx|
                  xlsx.write_worksheet('Asignaturas') do |sheet|
                    sheet << ['Período', 'Código', 'Asignatura', 'Créditos', 'Nota']
                    approved.each do |ar|
                      sheet << [
                        ar.enroll_academic_process&.academic_process&.period&.name || '—',
                        ar.subject.code,
                        ar.subject.name,
                        ar.subject.unit_credits,
                        ar.get_value_by_status
                      ]
                    end
                  end
                end
                send_data io.string,
                  filename: "asignaturas_#{user.ci}_#{Date.today}.xlsx",
                  type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
                next
              end

              @approved = approved.to_a
              render partial: 'rails_admin/main/recaudos_modal_body', layout: false

            else
              # --- Índice con tabs, búsqueda, orden y paginación ---
              @tab = TABS.include?(params[:tab]) ? params[:tab] : 'tesistas'
              @search = params[:q].to_s.strip.presence

              @sort = SORT_COLUMNS.key?(params[:sort]) ? params[:sort] : 'ci'
              @direction = (params[:direction] == 'desc') ? 'desc' : 'asc'
              order_sql = Arel.sql("#{SORT_COLUMNS[@sort]} #{@direction.upcase}")

              # Filtrado por entorno: cada admin solo ve las escuelas de su env_auth
              # (desarrollador => todas). Mismo mecanismo que admin.academic_processes/periods.
              school_ids = current_user.admin.schools_auh&.pluck(:id) || []

              base = Grade.joins(:study_plan, :user)
                          .includes(:study_plan, student: :user)
                          .where('study_plans.school_id': school_ids)
              if @search
                base = base.where("users.ci ILIKE :q OR users.first_name ILIKE :q OR users.last_name ILIKE :q",
                                  q: "%#{ActiveRecord::Base.sanitize_sql_like(@search)}%")
              end
              base = base.order(order_sql)

              scoped = case @tab
                       when 'tesistas'   then base.tesistas
                       when 'posibles'   then base.posible_graduando
                       when 'graduandos' then base.graduando
                       when 'graduados'  then base.graduado
                       end

              if params[:download] == 'xlsx'
                require 'xlsxtream'
                io = StringIO.new
                Xlsxtream::Workbook.open(io) do |xlsx|
                  xlsx.write_worksheet("Graduación #{@tab.titleize}") do |sheet|
                    sheet << ['Cédula', 'Apellidos', 'Nombre', 'Plan']
                    scoped.each do |g|
                      u = g.student.user
                      sheet << [u.ci, u.last_name, u.first_name, g.study_plan.code]
                    end
                  end
                end
                send_data io.string,
                  filename: "graduacion_#{@tab}_#{Date.today}.xlsx",
                  type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
                next
              end

              @grades = scoped.page(params[:page]).per(25)

              counts_base = Grade.of_schools(school_ids)
              @counts = {
                tesistas:   counts_base.tesistas.count,
                posibles:   counts_base.posible_graduando.count,
                graduandos: counts_base.graduando.count,
                graduados:  counts_base.graduado.count
              }

              render @action.template_name
            end
          end
        end
      end
    end
  end
end
