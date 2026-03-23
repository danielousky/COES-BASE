class DashboardDataService
  include ActionView::Helpers::DateHelper
  attr_reader :schools, :period, :academic_processes, :enrolling, :grading

  def initialize(admin, period_name)
    @schools = admin.schools_auh&.order(:name) || School.none
    @school_ids = @schools.pluck(:id)
    @period = Period.find_by(name: period_name)
    @academic_processes = AcademicProcess.where(school_id: @school_ids, period_id: @period&.id).to_a
    @process_ids = @academic_processes.map(&:id)
    @process_by_school = @academic_processes.index_by(&:school_id)
    @enrolling = @academic_processes.any?(&:enroll)
    @grading = @academic_processes.any?(&:active)
  end

  def enrollment_by_school
    return @enrollment_by_school if defined?(@enrollment_by_school)

    raw = EnrollAcademicProcess
      .where(academic_process_id: @process_ids)
      .joins(academic_process: :school)
      .group('schools.id', :enroll_status)
      .count

    @enrollment_by_school = build_school_hash(raw, %w[preinscrito reservado confirmado])
  end

  def enrollment_totals
    totals = { confirmado: 0, preinscrito: 0, reservado: 0, total: 0 }
    enrollment_by_school.each_value do |data|
      totals[:confirmado] += data[:confirmado]
      totals[:preinscrito] += data[:preinscrito]
      totals[:reservado] += data[:reservado]
      totals[:total] += data[:total]
    end
    totals
  end

  def section_stats
    return @section_stats if defined?(@section_stats)

    raw = Section
      .joins(course: :academic_process)
      .where('academic_processes.id': @process_ids)
      .group('academic_processes.school_id')
      .select(
        'academic_processes.school_id AS school_id',
        'COUNT(*) AS total',
        'SUM(CASE WHEN sections.qualified THEN 1 ELSE 0 END) AS qualified_count',
        'SUM(CASE WHEN sections.teacher_id IS NULL THEN 1 ELSE 0 END) AS no_teacher_count',
        'COALESCE(SUM(sections.capacity), 0) AS total_capacity',
        'COALESCE(SUM(sections.academic_records_count), 0) AS total_enrolled'
      )

    @section_stats = {}
    raw.each do |row|
      @section_stats[row.school_id] = {
        total: row.total.to_i,
        qualified: row.qualified_count.to_i,
        no_teacher: row.no_teacher_count.to_i,
        total_capacity: row.total_capacity.to_i,
        total_enrolled: row.total_enrolled.to_i,
        percentage: row.total.to_i > 0 ? (row.qualified_count.to_f / row.total * 100).round(0) : 0
      }
    end
    @section_stats
  end

  def section_totals
    totals = { total: 0, qualified: 0, no_teacher: 0, total_capacity: 0, total_enrolled: 0 }
    section_stats.each_value do |data|
      totals[:total] += data[:total]
      totals[:qualified] += data[:qualified]
      totals[:no_teacher] += data[:no_teacher]
      totals[:total_capacity] += data[:total_capacity]
      totals[:total_enrolled] += data[:total_enrolled]
    end
    totals[:percentage] = totals[:total] > 0 ? (totals[:qualified].to_f / totals[:total] * 100).round(0) : 0
    totals
  end

  def qualification_stats
    return @qualification_stats if defined?(@qualification_stats)

    @qualification_stats = AcademicRecord
      .joins(section: { course: :academic_process })
      .where('academic_processes.id': @process_ids)
      .group(:status)
      .count
      .transform_keys { |k| AcademicRecord.statuses.key(k) || k }
  end

  def approval_rate
    stats = qualification_stats
    aprobados = stats['aprobado'].to_i
    aplazados = stats['aplazado'].to_i
    pi = stats['perdida_por_inasistencia'].to_i
    coursed = aprobados + aplazados + pi
    return 0 if coursed.zero?

    (aprobados.to_f / coursed * 100).round(0)
  end

  def top_students(limit = 10, type_entity: nil)
    @top_students_cache ||= {}
    return @top_students_cache[[limit, type_entity]] if @top_students_cache.key?([limit, type_entity])

    scope = EnrollAcademicProcess
      .where(academic_process_id: @process_ids)
      .confirmado
      .where.not(weighted_average: [nil, 0])

    if type_entity
      scope = scope.joins(academic_process: :school)
        .where(schools: { type_entity: School.type_entities[type_entity] })
    end

    @top_students_cache[[limit, type_entity]] = scope
      .left_joins(academic_records: { section: { course: :subject } })
      .joins(:grade)
      .select(
        'enroll_academic_processes.*',
        'COUNT(academic_records.id) AS subjects_count',
        'COALESCE(SUM(subjects.unit_credits), 0) AS total_credits',
        'grades.weighted_average AS career_pp'
      )
      .group('enroll_academic_processes.id', 'grades.weighted_average')
      .order(
        Arel.sql('enroll_academic_processes.weighted_average DESC, COALESCE(SUM(subjects.unit_credits), 0) DESC, COUNT(academic_records.id) DESC, grades.weighted_average DESC')
      )
      .includes(grade: [:study_plan, { student: :user }])
      .limit(limit)
  end

  def perfect_score_count(type_entity: nil)
    @perfect_score_cache ||= {}
    return @perfect_score_cache[type_entity] if @perfect_score_cache.key?(type_entity)

    scope = EnrollAcademicProcess
      .where(academic_process_id: @process_ids)
      .confirmado
      .where(weighted_average: 20.0, efficiency: 1.0)

    if type_entity
      scope = scope.joins(academic_process: :school)
        .where(schools: { type_entity: School.type_entities[type_entity] })
    end

    @perfect_score_cache[type_entity] = scope.count
  end

  def school_type_entities
    @school_type_entities ||= @schools.reorder('').pluck(:type_entity).uniq
  end

  def alerts
    return [] if @process_ids.empty?

    items = []
    st = section_totals
    et = enrollment_totals

    if st[:no_teacher] > 0
      label = st[:no_teacher] == 1 ? 'sección sin profesor asignado' : 'secciones sin profesor asignado'
      items << { type: :warning, icon: 'fa-chalkboard-user',
                 text: "#{st[:no_teacher]} #{label}",
                 url: '/admin/section?scope=sin_profesor_asignado' }
    end

    pending_confirm = pending_confirmation_count
    if pending_confirm > 0
      items << { type: :info, icon: 'fa-user-clock',
                 text: "#{pending_confirm} preinscritos con pago reportado sin confirmar",
                 url: '/admin/enroll_academic_process?scope=preinscrito' }
    end

    over_capacity = sections_over_capacity_count
    if over_capacity > 0
      label = over_capacity == 1 ? 'sección excede capacidad' : 'secciones exceden capacidad'
      items << { type: :danger, icon: 'fa-exclamation-triangle',
                 text: "#{over_capacity} #{label}",
                 url: '/admin/section' }
    end

    items
  end

  def trend_data(last_n = 5)
    school_ids = @school_ids
    period_ids = AcademicProcess.where(school_id: school_ids)
      .joins(:period).order('periods.name DESC')
      .limit(last_n + 1).pluck(:period_id).uniq

    return { enrollment: [] } if period_ids.empty?

    enrollment = AcademicProcess.unscoped
      .where(school_id: school_ids, period_id: period_ids)
      .joins(:enroll_academic_processes, :period)
      .group('periods.name')
      .order('periods.name')
      .count('enroll_academic_processes.id')

    { enrollment: enrollment.values.last(last_n) }
  end

  def school_detail(school)
    school_id = school.id
    enroll = enrollment_by_school[school_id] || { confirmado: 0, preinscrito: 0, reservado: 0, total: 0 }
    secs = section_stats[school_id] || { total: 0, qualified: 0, no_teacher: 0, percentage: 0 }
    process = @process_by_school[school_id]

    {
      school: school,
      process: process,
      enrollment: enroll,
      sections: secs,
      process_name: process&.process_name
    }
  end

  # Admins activos: usuarios admin logueados recientemente
  def active_admins(current_user_id: nil)
    timeout = 2.hours.ago
    admins = Admin.joins(:user)
      .where('users.current_sign_in_at > ?', timeout)
      .where.not(users: { id: current_user_id })
      .includes(:user)
      .order('users.current_sign_in_at DESC')

    admin_user_ids = admins.pluck(:user_id).map(&:to_s)

    # Última acción de cada admin vía PaperTrail (DISTINCT ON de PostgreSQL)
    last_actions = {}
    if admin_user_ids.any?
      rows = PaperTrail::Version
        .select("DISTINCT ON (whodunnit) whodunnit, item_type, event, created_at")
        .where(whodunnit: admin_user_ids)
        .order(Arel.sql('whodunnit, created_at DESC'))
      rows.each { |v| last_actions[v.whodunnit] = v }
    end

    admins.map do |admin|
      user = admin.user
      version = last_actions[user.id.to_s]
      active = version && version.created_at > 15.minutes.ago

      {
        admin: admin,
        user: user,
        active: active,
        last_action: version ? format_action(version) : nil,
        last_action_at: version&.created_at
      }
    end
  end

  # JSON para endpoint de auto-refresh
  def enrollment_counts_json
    enrollment_by_school.transform_keys(&:to_s).merge('totals' => enrollment_totals)
  end

  def active_admins_json(current_user_id: nil)
    active_admins(current_user_id: current_user_id).map do |entry|
      user = entry[:user]
      {
        name: user.short_name,
        initials: "#{user.first_name&.first}#{user.last_name&.first}".upcase,
        role: I18n.t("activerecord.attributes.admin.roles.#{entry[:admin].role}", default: entry[:admin].role.humanize),
        active: entry[:active],
        last_action: entry[:last_action],
        last_action_ago: entry[:last_action_at] ? "Hace #{time_ago_in_words(entry[:last_action_at])}" : nil,
        avatar_url: nil
      }
    end
  end

  private

  def build_school_hash(raw_grouped, _statuses = nil)
    result = {}
    raw_grouped.each do |(school_id, status_idx), count|
      status_name = EnrollAcademicProcess.enroll_statuses.key(status_idx) || status_idx.to_s
      result[school_id] ||= { confirmado: 0, preinscrito: 0, reservado: 0, total: 0 }
      result[school_id][status_name.to_sym] = count
      result[school_id][:total] += count
    end
    result
  end

  def pending_confirmation_count
    EnrollAcademicProcess
      .where(academic_process_id: @process_ids)
      .preinscrito
      .joins(:payment_reports)
      .count
  end

  def format_action(version)
    # Si el evento es custom (paper_trail_event), ya tiene texto legible
    return version.event.sub(/\A¡/, '').sub(/!\z/, '').capitalize unless %w[create update destroy].include?(version.event)

    model_name = I18n.t(
      "activerecord.models.#{version.item_type.underscore}.one",
      default: version.item_type.titleize
    )
    case version.event
    when 'create' then "Registró #{model_name}"
    when 'update' then "Actualizó #{model_name}"
    when 'destroy' then "Eliminó #{model_name}"
    end
  end


  def sections_over_capacity_count
    Section
      .joins(course: :academic_process)
      .where('academic_processes.id': @process_ids)
      .where('sections.capacity > 0 AND sections.academic_records_count > sections.capacity')
      .count
  end
end
