class AuditTrailsController < ApplicationController
  before_action :authenticate_user!
  before_action :check_admin_permissions

  layout 'audit'
  def index
    @audit_trails = PaperTrail::Version.includes(:item)
                                      .order(created_at: :desc)
                                      .page(params[:page])
                                      .per(50)

    # Filtros
    if params[:event_type].present?
      @audit_trails = @audit_trails.where(event: params[:event_type])
    end

    if params[:item_type].present?
      @audit_trails = @audit_trails.where(item_type: params[:item_type])
    end

    if params[:user_id].present?
      @audit_trails = @audit_trails.where(whodunnit: params[:user_id])
    end

    if params[:date_from].present?
      @audit_trails = @audit_trails.where('created_at >= ?', Date.parse(params[:date_from]))
    end

    if params[:date_to].present?
      @audit_trails = @audit_trails.where('created_at <= ?', Date.parse(params[:date_to]).end_of_day)
    end

    # Estadísticas
    @statistics = get_audit_statistics
  end

  def show
    @audit_trail = PaperTrail::Version.find(params[:id])
  end

  def student_activities
    @student = Student.find(params[:student_id])
    @audit_trails = PaperTrail::Version.where(whodunnit: @student.user_id.to_s)
                                      .or(PaperTrail::Version.where(item_type: 'Student', item_id: @student.user_id))
                                      .or(PaperTrail::Version.where(item_type: 'Grade').joins("JOIN grades ON versions.item_id = grades.id AND grades.user_id = #{@student.user_id}"))
                                      .or(PaperTrail::Version.where(item_type: 'EnrollAcademicProcess').joins("JOIN enroll_academic_processes ON versions.item_id = enroll_academic_processes.id JOIN grades ON enroll_academic_processes.grade_id = grades.id AND grades.user_id = #{@student.user_id}"))
                                      .order(created_at: :desc)
                                      .page(params[:page])
                                      .per(30)
  end

  def export
    @audit_trails = PaperTrail::Version.includes(:item)
                                      .order(created_at: :desc)

    # Aplicar filtros si existen
    apply_filters

    respond_to do |format|
      format.csv do
        send_data generate_csv, filename: "audit_trails_#{Date.current.strftime('%Y%m%d')}.csv"
      end
      format.xlsx do
        send_data generate_xlsx, filename: "audit_trails_#{Date.current.strftime('%Y%m%d')}.xlsx"
      end
    end
  end

  def dashboard
    @statistics = get_audit_statistics
    @recent_activities = PaperTrail::Version.includes(:item)
                                           .order(created_at: :desc)
                                           .limit(20)
    @top_users = get_top_active_users
    @activity_by_type = get_activity_by_type
  end

  private

  def check_admin_permissions
    unless current_user&.admin?
      redirect_to root_path, alert: 'No tienes permisos para acceder a esta sección.'
    end
  end

  def apply_filters
    if params[:event_type].present?
      @audit_trails = @audit_trails.where(event: params[:event_type])
    end

    if params[:item_type].present?
      @audit_trails = @audit_trails.where(item_type: params[:item_type])
    end

    if params[:user_id].present?
      @audit_trails = @audit_trails.where(whodunnit: params[:user_id])
    end

    if params[:date_from].present?
      @audit_trails = @audit_trails.where('created_at >= ?', Date.parse(params[:date_from]))
    end

    if params[:date_to].present?
      @audit_trails = @audit_trails.where('created_at <= ?', Date.parse(params[:date_to]).end_of_day)
    end
  end

  def get_audit_statistics
    start_date = 30.days.ago
    
    {
      total_events: PaperTrail::Version.where(created_at: start_date..).count,
      user_registrations: PaperTrail::Version.where(item_type: 'User', event: 'create', created_at: start_date..).count,
      student_registrations: PaperTrail::Version.where(item_type: 'Student', event: 'create', created_at: start_date..).count,
      logins: PaperTrail::Version.where("object_changes LIKE ?", '%sign_in_count%').where(created_at: start_date..).count,
      academic_events: PaperTrail::Version.where(item_type: ['Grade', 'EnrollAcademicProcess', 'AcademicRecord'], created_at: start_date..).count,
      document_events: PaperTrail::Version.where("object_changes LIKE ? OR object_changes LIKE ?", '%document%', '%download%').where(created_at: start_date..).count,
      events_today: PaperTrail::Version.where(created_at: Date.current.beginning_of_day..).count,
      events_this_week: PaperTrail::Version.where(created_at: 1.week.ago..).count
    }
  end

  def get_top_active_users
    PaperTrail::Version.where(created_at: 30.days.ago..)
                      .where.not(whodunnit: nil)
                      .group(:whodunnit)
                      .count
                      .sort_by { |k, v| -v }
                      .first(10)
                      .map do |user_id, count|
      user = User.find_by(id: user_id)
      {
        user: user,
        count: count,
        name: user ? "#{user.first_name} #{user.last_name}" : "Usuario ID: #{user_id}"
      }
    end
  end

  def get_activity_by_type
    PaperTrail::Version.where(created_at: 30.days.ago..)
                      .group(:item_type)
                      .count
                      .sort_by { |k, v| -v }
  end

  def generate_csv
    require 'csv'
    
    CSV.generate do |csv|
      csv << ['Fecha', 'Hora', 'Evento', 'Tipo de Registro', 'Usuario', 'Detalles']
      
      @audit_trails.each do |trail|
        user_name = trail.whodunnit.present? ? 
          (User.find_by(id: trail.whodunnit)&.full_name || "Usuario ID: #{trail.whodunnit}") : 
          "Sistema"
        
        csv << [
          trail.created_at.strftime('%d/%m/%Y'),
          trail.created_at.strftime('%H:%M:%S'),
          trail.event,
          trail.item_type,
          user_name,
          trail.object_changes.present? ? trail.object_changes.truncate(100) : 'Sin cambios'
        ]
      end
    end
  end

  def generate_xlsx
    require 'axlsx'
    
    package = Axlsx::Package.new
    workbook = package.workbook
    
    workbook.add_worksheet(name: "Bitácoras") do |sheet|
      # Encabezados
      sheet.add_row ['Fecha', 'Hora', 'Evento', 'Tipo de Registro', 'Usuario', 'Detalles']
      
      # Datos
      @audit_trails.each do |trail|
        user_name = trail.whodunnit.present? ? 
          (User.find_by(id: trail.whodunnit)&.full_name || "Usuario ID: #{trail.whodunnit}") : 
          "Sistema"
        
        sheet.add_row [
          trail.created_at.strftime('%d/%m/%Y'),
          trail.created_at.strftime('%H:%M:%S'),
          trail.event,
          trail.item_type,
          user_name,
          trail.object_changes.present? ? trail.object_changes.truncate(100) : 'Sin cambios'
        ]
      end
    end
    
    package.to_stream.read
  end
end

