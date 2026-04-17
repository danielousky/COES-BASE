class Section
  class BitacoraQuery
    DEFAULT_PER_PAGE = 50
    TABS = %w[general students].freeze
    AR_RELEVANT_SQL = "(event = 'destroy' OR object_changes ~ E'status:\\n- [0-9]+\\n- (3|4)(\\\\s|$)')".freeze

    def initialize(section, params = {})
      @section = section
      @student_ci = params[:student_ci].presence
      @tab = params[:tab].presence.to_s
      @tab = 'general' unless TABS.include?(@tab)
      @all = params[:all].present?
      @page = params[:page].presence || '1'
      @per_page = (params[:per_page].presence || DEFAULT_PER_PAGE).to_i
    end

    attr_reader :tab

    def call
      versions = scope_for_tab(@tab)
      versions = versions.order(created_at: :desc, id: :desc)
      paginated_versions = @all ? versions : versions.page(@page).per(@per_page)
      user_lookup = build_user_lookup(paginated_versions)
      item_cache = build_item_cache(paginated_versions)
      proxies = paginated_versions.map do |version|
        Section::BitacoraProxy.new(version, user_lookup: user_lookup, item_cache: item_cache)
      end
      wrap_pagination(proxies, paginated_versions)
    end

    def total_count
      scope_for_tab(@tab).count
    end

    def tab_counts
      {
        'general'  => scope_for_tab('general').count,
        'students' => scope_for_tab('students').count
      }
    end

    def focused_student
      return nil unless @student_ci
      @focused_student ||= User.find_by(ci: @student_ci)
    end

    private

    def scope_for_tab(tab)
      case tab
      when 'general'  then general_scope
      when 'students' then students_scope
      end
    end

    def general_scope
      PaperTrail::Version.where(item_type: 'Section', item_id: @section.id)
    end

    def students_scope
      q_ids  = @student_ci ? student_qualification_ids : qualification_ids
      ar_ids = @student_ci ? student_academic_record_ids : academic_record_ids

      q_scope  = PaperTrail::Version.where(item_type: 'Qualification', item_id: safe_ids(q_ids))
      ar_scope = PaperTrail::Version.where(item_type: 'AcademicRecord', item_id: safe_ids(ar_ids))
                                    .where(AR_RELEVANT_SQL)

      PaperTrail::Version
        .from(Arel.sql("(#{q_scope.to_sql} UNION ALL #{ar_scope.to_sql}) AS versions"))
    end

    def academic_record_ids
      @academic_record_ids ||= @section.academic_record_ids
    end

    def qualification_ids
      @qualification_ids ||= Qualification.where(academic_record_id: academic_record_ids).pluck(:id)
    end

    def student_academic_record_ids
      @student_academic_record_ids ||= AcademicRecord.joins(:user)
                                                     .where(section_id: @section.id)
                                                     .where('users.ci = ?', @student_ci)
                                                     .pluck(:id)
    end

    def student_qualification_ids
      @student_qualification_ids ||= Qualification.where(academic_record_id: student_academic_record_ids).pluck(:id)
    end

    def safe_ids(ids)
      ids.presence || [0]
    end

    def build_user_lookup(versions)
      ids = versions.map(&:whodunnit).compact.select { |w| w.to_s.match?(/\A\d+\z/) }.uniq
      return {} if ids.empty?
      User.where(id: ids).index_by { |u| u.id.to_s }
    end

    def build_item_cache(versions)
      cache = Hash.new { |h, k| h[k] = {} }
      versions.group_by(&:item_type).each do |item_type, vs|
        klass = item_type.safe_constantize
        next unless klass
        ids = vs.map(&:item_id).uniq
        scope = klass.unscoped
        scope = scope.includes(includes_for(item_type)) if includes_for(item_type)
        scope.where(id: ids).each { |record| cache[item_type][record.id] = record }
      end
      cache
    end

    def includes_for(item_type)
      case item_type
      when 'Qualification'  then { academic_record: { student: :user } }
      when 'AcademicRecord' then { student: :user }
      end
    end

    def wrap_pagination(proxies, paginated_versions)
      if @all
        Kaminari.paginate_array(proxies, total_count: proxies.size)
      else
        total = paginated_versions.try(:total_count) || proxies.size
        Kaminari.paginate_array(proxies, total_count: total)
                .page(@page)
                .per(@per_page)
      end
    end
  end
end
